import argparse
import atexit
import collections
import collections.abc
import copy
import datetime
import getpass
import hashlib
import http.client
import io
import json
import os
import getpass
import pathlib
import platform
import pprint
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import time
import types

import version


## Imports not in standard library ##

# List of dependency problems.
depfails = []

# Lark is bundled or provided by package dependencies, so assume it's always
# importable. There used to be a conflicting package on PyPI called "lark",
# but it's gone now [1]. However, verify the version we got.
#
# [1]: https://github.com/lark-parser/lark/issues/505
import lark
LARK_MIN = (0,  7, 1)
LARK_MAX = (0, 12, 0)
lark_version = tuple(int(i) for i in lark.__version__.split("."))
if (not LARK_MIN <= lark_version <= LARK_MAX):
   depfails.append(("bad", 'found Python module "lark" version %d.%d.%d but need between %d.%d.%d and %d.%d.%d inclusive' % (lark_version + LARK_MIN + LARK_MAX)))

# Requests is not bundled, so this noise makes the file parse and
# --version/--help work even if it's not installed.
try:
   import requests
   import requests.auth
   import requests.exceptions
except ImportError:
   depfails.append(("missing", 'Python module "requests"'))
   # Mock up a requests.auth module so the rest of the file parses.
   requests = types.ModuleType("requests")
   requests.auth = types.ModuleType("requests.auth")
   requests.auth.AuthBase = object


## Constants ##

# Architectures. This maps the "machine" field returned by uname(2), also
# available as "uname -m" and platform.machine(), into architecture names that
# image registries use. It is incomplete (see e.g. [1], which is itself
# incomplete) but hopefully includes most architectures encountered in
# practice [e.g. 2]. Registry architecture and variant are separated by a
# slash. Note it is *not* 1-to-1: multiple uname(2) architectures map to the
# same registry architecture.
#
# [1]: https://stackoverflow.com/a/45125525
# [2]: https://github.com/docker-library/bashbrew/blob/v0.1.0/vendor/github.com/docker-library/go-dockerlibrary/architecture/oci-platform.go
ARCH_MAP = { "x86_64":    "amd64",
             "armv5l":    "arm/v5",
             "armv6l":    "arm/v6",
             "aarch32":   "arm/v7",
             "armv7l":    "arm/v7",
             "aarch64":   "arm64/v8",
             "armv8l":    "arm64/v8",
             "i386":      "386",
             "i686":      "386",
             "mips64le":  "mips64le",
             "ppc64le":   "ppc64le",
             "s390x":     "s390x" }  # a.k.a. IBM Z

# String to use as hint when we throw an error that suggests a bug.
BUG_REPORT_PLZ = "please report this bug: https://github.com/hpc/charliecloud/issues"

# This is a general grammar for all the parsing we need to do. As such, you
# must prepend a start rule before use.
GRAMMAR = r"""

/// Image references ///

// Note: Hostnames with no dot and no port get parsed as a hostname, which
// is wrong; it should be the first path component. We patch this error later.
// FIXME: Supposedly this can be fixed with priorities, but I couldn't get it
// to work with brief trying.
image_ref: ir_hostport? ir_path? ir_name ( ir_tag | ir_digest )?
ir_hostport: IR_HOST ( ":" IR_PORT )? "/"
ir_path: ( IR_PATH_COMPONENT "/" )+
ir_name: IR_PATH_COMPONENT
ir_tag: ":" IR_TAG
ir_digest: "@sha256:" HEX_STRING
IR_HOST: /[A-Za-z0-9_.-]+/
IR_PORT: /[0-9]+/
IR_PATH_COMPONENT: /[a-z0-9_.-]+/
IR_TAG: /[A-Za-z0-9_.-]+/

/// Dockerfile ///

// First instruction must be ARG or FROM, but that is not a syntax error.
dockerfile: _NEWLINES? ( directive | comment )* ( instruction | comment )*

?instruction: _WS? ( arg | copy | env | from_ | run | shell | workdir | uns_forever | uns_yet )

directive.2: _WS? "#" _WS? DIRECTIVE_NAME "=" _line _NEWLINES
DIRECTIVE_NAME: ( "escape" | "syntax" )
comment: _WS? _COMMENT_BODY _NEWLINES
_COMMENT_BODY: /#[^\n]*/

copy: "COPY"i ( _WS option )* _WS ( copy_list | copy_shell ) _NEWLINES
copy_list.2: _string_list
copy_shell: WORD ( _WS WORD )+

arg: "ARG"i _WS ( arg_bare | arg_equals ) _NEWLINES
arg_bare: WORD
arg_equals: WORD "=" ( WORD | STRING_QUOTED )

env: "ENV"i _WS ( env_space | env_equalses ) _NEWLINES
env_space: WORD _WS _line
env_equalses: env_equals ( _WS env_equals )*
env_equals: WORD "=" ( WORD | STRING_QUOTED )

from_: "FROM"i ( _WS option )* _WS image_ref [ _WS from_alias ] _NEWLINES
from_alias: "AS"i _WS IR_PATH_COMPONENT  // FIXME: undocumented; this is guess

run: "RUN"i _WS ( run_exec | run_shell ) _NEWLINES
run_exec.2: _string_list
run_shell: _line

shell: "SHELL"i _WS _string_list _NEWLINES

workdir: "WORKDIR"i _WS _line _NEWLINES

uns_forever: UNS_FOREVER _WS _line _NEWLINES
UNS_FOREVER: ( "EXPOSE"i | "HEALTHCHECK"i | "MAINTAINER"i | "STOPSIGNAL"i | "USER"i | "VOLUME"i )

uns_yet: UNS_YET _WS _line _NEWLINES
UNS_YET: ( "ADD"i | "CMD"i | "ENTRYPOINT"i | "LABEL"i | "ONBUILD"i )

/// Common ///

option: "--" OPTION_KEY "=" OPTION_VALUE
OPTION_KEY: /[a-z]+/
OPTION_VALUE: /[^ \t\n]+/

// Matching lines in the face of continuations is surprisingly hairy. Notes:
//
//   1. The underscore prefix means the rule is always inlined (i.e., removed
//      and children become children of its parent).
//
//   2. LINE_CHUNK must not match any characters that _LINE_CONTINUE does.
//
//   3. This is very sensitive to the location of repetition. Moving the plus
//      either to the entire regex (i.e., “/(...)+/”) or outside the regex
//      (i.e., ”/.../+”) gave parse errors.
//
_line: ( _LINE_CONTINUE | LINE_CHUNK )+
LINE_CHUNK: /[^\\\n]+|(\\(?![ \t]+\n))+/

HEX_STRING: /[0-9A-Fa-f]+/
WORD: /[^ \t\n=]/+

_string_list: "[" _WS? STRING_QUOTED ( "," _WS? STRING_QUOTED )* _WS? "]"

_WSH: /[ \t]/+                   // sequence of horizontal whitespace
_LINE_CONTINUE: "\\" _WSH? "\n"  // line continuation
_WS: ( _WSH | _LINE_CONTINUE )+  // horizontal whitespace w/ line continuations
_NEWLINES: ( _WS? "\n" )+        // sequence of newlines

%import common.ESCAPED_STRING -> STRING_QUOTED
"""

# Chunk size in bytes when streaming HTTP. Progress meter is updated once per
# chunk, which means the display is updated roughly every 20s at 100 Kbit/s
# and every 2s at 1Mbit/s; beyond that, the once-per-second display throttling
# takes over.
HTTP_CHUNK_SIZE = 256 * 1024

# Minimum Python version. NOTE: Keep in sync with configure.ac.
PYTHON_MIN = (3,6)

# Content types for some stuff we care about.
# See: https://github.com/opencontainers/image-spec/blob/main/media-types.md
TYPES_MANIFEST = \
   {"docker2": "application/vnd.docker.distribution.manifest.v2+json",
    "oci1":    "application/vnd.oci.image.manifest.v1+json"}
TYPES_INDEX = \
   {"docker2": "application/vnd.docker.distribution.manifest.list.v2+json",
    "oci1":    "application/vnd.oci.image.index.v1+json"}
TYPE_CONFIG = "application/vnd.docker.container.image.v1+json"
TYPE_LAYER = "application/vnd.docker.image.rootfs.diff.tar.gzip"

# Top-level directories we create if not present.
STANDARD_DIRS = { "bin", "dev", "etc", "mnt", "proc", "sys", "tmp", "usr" }

# Storage directory format version. We refuse to operate on storage
# directories with non-matching versions. Increment this number when the
# format changes non-trivially.
STORAGE_VERSION = 2


## Globals ##

# Active architecture (both using registry vocabulary)
arch = None       # requested by user
arch_host = None  # of host

# FIXME: currently set in ch-image :P
CH_BIN = None
CH_RUN = None

# Logging; set using init() below.
verbose = 0          # Verbosity level.
log_festoon = False  # If true, prepend pid and timestamp to chatter.
log_fp = sys.stderr  # File object to print logs to.

# Verify TLS certificates? Passed to requests.
tls_verify = True


## Exceptions ##

class No_Fatman_Error(Exception): pass
class Not_In_Registry_Error(Exception): pass


## Classes ##

class Credentials:

   __slots__ = ("password",
                "username")

   def __init__(self):
      self.username = None
      self.password = None

   def get(self):
      # If stored, return those.
      if (self.username is not None):
         username = self.username
         password = self.password
      else:
         try:
            # Otherwise, use environment variables.
            username = os.environ["CH_IMAGE_USERNAME"]
            password = os.environ["CH_IMAGE_PASSWORD"]
         except KeyError:
            # Finally, prompt the user.
            # FIXME: This hangs in Bats despite sys.stdin.isatty() == True.
            try:
               username = input("\nUsername: ")
            except KeyboardInterrupt:
               FATAL("authentication cancelled")
            password = getpass.getpass("Password: ")
         if (not password_many):
            # Remember the credentials.
            self.username = username
            self.password = password
      return (username, password)


class HelpFormatter(argparse.HelpFormatter):

   def __init__(self, *args, **kwargs):
      # max_help_position is undocumented but I don't know how else to do this.
      #kwargs["max_help_position"] = 26
      super().__init__(max_help_position=26, *args, **kwargs)

   # Suppress duplicate metavar printing when option has both short and long
   # flavors. E.g., instead of:
   #
   #   -s DIR, --storage DIR  set builder internal storage directory to DIR
   #
   # print:
   #
   #   -s, --storage DIR      set builder internal storage directory to DIR
   #
   # From https://stackoverflow.com/a/31124505.
   def _format_action_invocation(self, action):
      if (not action.option_strings or action.nargs == 0):
         return super()._format_action_invocation(action)
      default = self._get_default_metavar_for_optional(action)
      args_string = self._format_args(action, default)
      return ', '.join(action.option_strings) + ' ' + args_string


class Image:
   """Container image object.

      Constructor arguments:

        ref........... Image_Ref object to identify the image.

        unpack_path .. Directory to unpack the image in; if None, infer path
                       in storage dir from ref."""

   __slots__ = ("metadata",
                "ref",
                "unpack_path")

   def __init__(self, ref, unpack_path=None):
      assert isinstance(ref, Image_Ref)
      self.ref = ref
      if (unpack_path is not None):
         self.unpack_path = Path(unpack_path)
      else:
         self.unpack_path = storage.unpack(self.ref)
      self.metadata_init()

   @property
   def metadata_path(self):
      return self.unpack_path // "ch"

   @property
   def unpack_exist_p(self):
      return os.path.exists(self.unpack_path)

   def __str__(self):
      return str(self.ref)

   @staticmethod
   def unpacked_p(imgdir):
      "Return True if imgdir looks like an unpacked image, False otherwise."
      return (    os.path.isdir(imgdir)
              and os.path.isdir(imgdir // 'bin')
              and os.path.isdir(imgdir // 'dev')
              and os.path.isdir(imgdir // 'usr'))

   def commit(self):
      "Commit the current unpack directory into the layer cache."
      assert False, "unimplemented"

   def copy_unpacked(self, other):
      """Copy image other to my unpack directory. other can be either a path
         (string or Path object) or an Image object; in the latter case
         other.unpack_pach is used. other need not be a valid image; the
         essentials will be created if needed."""
      if (isinstance(other, str) or isinstance(other, Path)):
         src_path = other
      else:
         src_path = other.unpack_path
      self.unpack_clear()
      VERBOSE("copying image: %s -> %s" % (src_path, self.unpack_path))
      copytree(src_path, self.unpack_path, symlinks=True)
      self.unpack_init()

   def layers_open(self, layer_tars):
      """Open the layer tarballs and read some metadata (which unfortunately
         means reading the entirety of every file). Return an OrderedDict:

           keys:    layer hash (full)
           values:  namedtuple with two fields:
                      fp:       open TarFile object
                      members:  sequence of members (OrderedSet)

         Empty layers are skipped.

         Important note: TarFile.extractall() extracts the given members in
         the order they are specified, so we need to preserve their order from
         the file, as returned by getmembers(). We also need to quickly remove
         members we don't want from this sequence. Thus, we use the OrderedSet
         class defined in this module."""
      TT = collections.namedtuple("TT", ["fp", "members"])
      layers = collections.OrderedDict()
      # Schema version one (v1) allows one or more empty layers for Dockerfile
      # entries like CMD (https://github.com/containers/skopeo/issues/393).
      # Unpacking an empty layer doesn't accomplish anything so we ignore them.
      empty_cnt = 0
      for (i, path) in enumerate(layer_tars, start=1):
         lh = os.path.basename(path).split(".", 1)[0]
         lh_short = lh[:7]
         INFO("layer %d/%d: %s: listing" % (i, len(layer_tars), lh_short))
         try:
            fp = TarFile.open(path)
            members = OrderedSet(fp.getmembers())  # reads whole file :(
         except tarfile.TarError as x:
            FATAL("cannot open: %s: %s" % (path, x))
         if (lh in layers and len(members) > 0):
            FATAL("duplicate non-empty layer %s" % lh)
         if (len(members) > 0):
            layers[lh] = TT(fp, members)
         else:
            empty_cnt += 1
      VERBOSE("skipped %d empty layers" % empty_cnt)
      return layers

   def metadata_init(self):
      "Initialize empty metadata structure."
      # Elsewhere can assume the existence and types of everything here.
      self.metadata = { "arch": arch_host.split("/")[0],  # no variant
                        "cwd": "/",
                        "env": dict(),
                        "history": list(),
                        "labels": dict(),
                        "shell": ["/bin/sh", "-c"],
                        "volumes": list() }  # set isn't JSON-serializable

   def metadata_load(self):
      """Load metadata file, replacing the existing metadata object. If
         metadata doesn't exist, warn and use defaults."""
      path = self.metadata_path // "metadata.json"
      if (not path.exists()):
         WARNING("no metadata to load; using defaults")
         self.metadata_init()
         return
      self.metadata = json_from_file(path, "metadata")
      self.metadata.setdefault("history", list())  # upgrade pre-PR #1215

   def metadata_merge_from_config(self, config):
      """Interpret all the crap in the config data structure that is meaingful
         to us, and add it to self.metadata. Ignore anything we expect in
         config that's missing."""
      def get(*keys):
         d = config
         keys = list(keys)
         while (len(keys) > 1):
            try:
               d = d[keys.pop(0)]
            except KeyError:
               return None
         assert (len(keys) == 1)
         return d.get(keys[0])
      def set_(dst_key, *src_keys):
         v = get(*src_keys)
         if (v is not None and v != ""):
            self.metadata[dst_key] = v
      if ("config" not in config):
         FATAL("config missing key 'config'")
      # architecture
      set_("arch", "architecture")
      # $CWD
      set_("cwd", "config", "WorkingDir")
      # environment
      env = get("config", "Env")
      if (env is not None):
         for line in env:
            try:
               (k,v) = line.split("=", maxsplit=1)
            except AttributeError:
               FATAL("can't parse config: bad Env line: %s" % line)
            self.metadata["env"][k] = v
      # History.
      if ("history" not in config):
         FATAL("invalid config: missing history")
      self.metadata["history"] = config["history"]
      # labels
      set_("labels", "config", "Labels")  # copy reference
      # shell
      set_("shell", "config", "Shell")
      # Volumes. FIXME: Why is this a dict with empty dicts as values?
      vols = get("config", "Volumes")
      if (vols is not None):
         for k in config["config"]["Volumes"].keys():
            self.metadata["volumes"].append(k)

   def metadata_replace(self, config_json):
      self.metadata_init()
      if (config_json is None):
         INFO("no config found; initializing empty metadata")
      else:
         # Copy pulled config file into the image so we still have it.
         path = self.metadata_path // "config.pulled.json"
         copy2(config_json, path)
         VERBOSE("pulled config path: %s" % path)
         self.metadata_merge_from_config(json_from_file(path, "config"))
      self.metadata_save()

   def metadata_save(self):
      """Dump image's metadata to disk, including the main data structure but
         also all auxiliary files, e.g. ch/environment."""
      # Serialize. We take care to pretty-print this so it can (sometimes) be
      # parsed by simple things like grep and sed.
      out = json.dumps(self.metadata, indent=2, sort_keys=True)
      DEBUG("metadata:\n%s" % out)
      # Main metadata file.
      path = self.metadata_path // "metadata.json"
      VERBOSE("writing metadata file: %s" % path)
      file_write(path, out + "\n")
      # /ch/environment
      path = self.metadata_path // "environment"
      VERBOSE("writing environment file: %s" % path)
      file_write(path, (  "\n".join("%s=%s" % (k,v) for (k,v)
                                    in sorted(self.metadata["env"].items()))
                        + "\n"))
      # mkdir volumes
      VERBOSE("ensuring volume directories exist")
      for path in self.metadata["volumes"]:
         mkdirs(self.unpack_path // path)

   def tarballs_write(self, tarball_dir):
      """Write one uncompressed tarball per layer to tarball_dir. Return a
         sequence of tarball basenames, with the lowest layer first."""
      # FIXME: Yes, there is only one layer for now and we'll need to update
      # it when (if) we have multiple layers. But, I wanted the interface to
      # support multiple layers.
      base = "%s.tar" % self.ref.for_path
      path = tarball_dir // base
      try:
         INFO("layer 1/1: gathering")
         VERBOSE("writing tarball: %s" % path)
         fp = TarFile.open(path, "w", format=tarfile.PAX_FORMAT)
         unpack_path = self.unpack_path.resolve()  # aliases use symlinks
         VERBOSE("canonicalized unpack path: %s" % unpack_path)
         fp.add_(unpack_path, arcname=".")
         fp.close()
      except OSError as x:
         FATAL("can't write tarball: %s" % x.strerror)
      return [base]

   def unpack(self, layer_tars, last_layer=None):
      """Unpack config_json (path to JSON config file) and layer_tars
         (sequence of paths to tarballs, with lowest layer first) into the
         unpack directory, validating layer contents and dealing with
         whiteouts. Empty layers are ignored. Overwrite any existing image in
         the unpack directory."""
      if (last_layer is None):
         last_layer = sys.maxsize
      INFO("flattening image")
      self.unpack_clear()
      self.unpack_layers(layer_tars, last_layer)
      self.unpack_init()

   def unpack_clear(self):
      """If the unpack directory does not exist, do nothing. If the unpack
         directory is already an image, remove it. Otherwise, error."""
      if (not os.path.exists(self.unpack_path)):
         VERBOSE("no image found: %s" % self.unpack_path)
      else:
         if (not os.path.isdir(self.unpack_path)):
            FATAL("can't flatten: %s exists but is not a directory"
                  % self.unpack_path)
         if (not self.unpacked_p(self.unpack_path)):
            FATAL("can't flatten: %s exists but does not appear to be an image"
                  % self.unpack_path)
         VERBOSE("removing existing image: %s" % self.unpack_path)
         rmtree(self.unpack_path)

   def unpack_init(self):
      """Initialize the unpack directory, which must exist. Any setup already
         present will be left unchanged. After this, self.unpack_path is a
         valid Charliecloud image directory."""
      # Metadata directory.
      mkdir(self.unpack_path // "ch")
      file_ensure_exists(self.unpack_path // "ch/environment")
      # Essential directories & mount points. Do nothing if something already
      # exists, without dereferencing, in case it's a symlink, which will work
      # for bind-mount later but won't resolve correctly now outside the
      # container (e.g. linuxcontainers.org images; issue #1015).
      #
      # WARNING: Keep in sync with shell scripts.
      for d in list(STANDARD_DIRS) + ["mnt/%d" % i for i in range(10)]:
         d = self.unpack_path // d
         if (not os.path.lexists(d)):
            mkdirs(d)
      file_ensure_exists(self.unpack_path // "etc/hosts")
      file_ensure_exists(self.unpack_path // "etc/resolv.conf")

   def unpack_layers(self, layer_tars, last_layer):
      layers = self.layers_open(layer_tars)
      self.validate_members(layers)
      self.whiteouts_resolve(layers)
      mkdir(self.unpack_path)  # create directory in case no layers
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         lh_short = lh[:7]
         if (i > last_layer):
            INFO("layer %d/%d: %s: skipping per --last-layer"
                 % (i, len(layers), lh_short))
         else:
            INFO("layer %d/%d: %s: extracting" % (i, len(layers), lh_short))
            try:
               fp.extractall(path=self.unpack_path, members=members)
            except OSError as x:
               FATAL("can't extract layer %d: %s" % (i, x.strerror))

   def validate_members(self, layers):
      INFO("validating tarball members")
      top_dirs = set()
      VERBOSE("pass 1: canonicalizing member paths")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         abs_ct = 0
         for m in list(members):   # copy b/c we remove items from the set
            # Remove members with empty paths.
            if (len(m.name) == 0):
               WARNING("layer %d/%d: %s: skipping member with empty path"
                       % (i, len(layers), lh[:7]))
               members.remove(m)
            # Convert member paths to Path objects for easier processing.
            # Note: In my testing, parsing a string into a Path object took
            # about 2.5µs, so this should be plenty fast.
            m.name = Path(m.name)
            # Reject members with up-levels.
            if (".." in m.name.parts):
               FATAL("rejecting up-level member: %s: %s" % (fp.name, m.name))
            # Correct absolute paths.
            if (m.name.is_absolute()):
               m.name = m.name.relative_to("/")
            # Record top-level directory.
            if (len(m.name.parts) > 1 or m.isdir()):
               top_dirs.add(m.name.first)
         if (abs_ct > 0):
            WARNING("layer %d/%d: %s: fixed %d absolute member paths"
                    % (i, len(layers), lh[:7], abs_ct))
      top_dirs.discard(None)  # ignore “.”
      # Convert to tarbomb if (1) there is a single enclosing directory and
      # (2) that directory is not one of the standard directories, e.g. to
      # allow images containing just “/bin/fooprog”.
      if (len(top_dirs) != 1 or not top_dirs.isdisjoint(STANDARD_DIRS)):
         VERBOSE("pass 2: conversion to tarbomb not needed")
      else:
         VERBOSE("pass 2: converting to tarbomb")
         for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
            for m in members:
               if (len(m.name.parts) > 0):  # ignore “.”
                  m.name = Path(*m.name.parts[1:])  # strip first component
      VERBOSE("pass 3: analyzing members")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         dev_ct = 0
         link_fix_ct = 0
         for m in list(members):  # copy again
            m.name = str(m.name)  # other code assumes strings
            if (m.isdev()):
               # Device or FIFO: Ignore.
               dev_ct += 1
               VERBOSE("ignoring device file: %s" % m.name)
               members.remove(m)
               continue
            elif (m.issym() or m.islnk()):
               link_fix_ct += TarFile.fix_link_target(m, fp.name)
            elif (m.isdir()):
               # Directory: Fix bad permissions (hello, Red Hat).
               m.mode |= 0o700
            elif (m.isfile()):
               # Regular file: Fix bad permissions (HELLO RED HAT!!).
               m.mode |= 0o600
            else:
               FATAL("unknown member type: %s" % m.name)
            # Discard anything under /dev. Docker puts regular files and
            # directories in here on "docker export". Note leading slashes
            # already taken care of in TarFile.fix_member_path() above.
            if (re.search(r"^(\./)?dev/.", m.name)):
               VERBOSE("ignoring member under /dev: %s" % m.name)
               members.remove(m)
               continue
            TarFile.fix_member_uidgid(m)
         if (dev_ct > 0):
            WARNING("layer %d/%d: %s: ignored %d devices and/or FIFOs"
                    % (i, len(layers), lh[:7], dev_ct))
         if (link_fix_ct > 0):
            WARNING(("layer %d/%d: %s: changed %d absolute symbolic and/or hard links to relative"
                     % (i, len(layers), lh[:7], link_fix_ct)),
                    "specify -vv for details")

   def whiteout_rm_prefix(self, layers, max_i, prefix):
      """Ignore members of all layers from 1 to max_i inclusive that have path
         prefix of prefix. For example, if prefix is foo/bar, then ignore
         foo/bar and foo/bar/baz but not foo/barbaz. Return count of members
         ignored."""
      TRACE("finding members with prefix: %s" % prefix)
      prefix = os.path.normpath(prefix)  # "./foo" == "foo"
      ignore_ct = 0
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         if (i > max_i): break
         members2 = list(members)  # copy b/c we'll alter members
         for m in members2:
            if (prefix_path(prefix, m.name)):
               ignore_ct += 1
               members.remove(m)
               TRACE("layer %d/%d: %s: ignoring %s"
                     % (i, len(layers), lh[:7], m.name))
      return ignore_ct

   def whiteouts_resolve(self, layers):
      """Resolve whiteouts. See:
         https://github.com/opencontainers/image-spec/blob/master/layer.md"""
      INFO("resolving whiteouts")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         wo_ct = 0
         ig_ct = 0
         members2 = list(members)  # copy b/c we'll alter members
         for m in members2:
            dir_ = os.path.dirname(m.name)
            filename = os.path.basename(m.name)
            if (filename.startswith(".wh.")):
               wo_ct += 1
               members.remove(m)
               if (filename == ".wh..wh..opq"):
                  # "Opaque whiteout": remove contents of dir_.
                  DEBUG("found opaque whiteout: %s" % m.name)
                  ig_ct += self.whiteout_rm_prefix(layers, i - 1, dir_)
               else:
                  # "Explicit whiteout": remove same-name file without ".wh.".
                  DEBUG("found explicit whiteout: %s" % m.name)
                  ig_ct += self.whiteout_rm_prefix(layers, i - 1,
                                                   dir_ + "/" + filename[4:])
         if (wo_ct > 0):
            VERBOSE("layer %d/%d: %s: %d whiteouts; %d members ignored"
                    % (i, len(layers), lh[:7], wo_ct, ig_ct))

   def unpack_create_ok(self):
      """Ensure the unpack directory can be created. If the unpack directory
         is already an image, remove it."""
      if (not self.unpack_exist_p):
         VERBOSE("creating new image: %s" % self.unpack_path)
      else:
         if (not os.path.isdir(self.unpack_path)):
            FATAL("can't flatten: %s exists but is not a directory"
                  % self.unpack_path)
         if (not self.unpacked_p(self.unpack_path)):
            FATAL("can't flatten: %s exists but does not appear to be an image"
                  % self.unpack_path)
         VERBOSE("replacing existing image: %s" % self.unpack_path)
         rmtree(self.unpack_path)

   def unpack_delete(self):
      VERBOSE("unpack path: %s" % self.unpack_path)
      if (not self.unpack_exist_p):
         FATAL("%s image not found" % self.ref)
      if (self.unpacked_p(self.unpack_path)):
         INFO("deleting image: %s" % self.ref)
         rmtree(self.unpack_path)
      else:
         FATAL("storage directory seems broken: not an image: %s" % self.ref)

   def unpack_create(self):
      "Ensure the unpack directory exists, replacing or creating if needed."
      self.unpack_create_ok()
      mkdir(self.unpack_path)


class Image_Ref:
   """Reference to an image in a remote repository.

      The constructor takes one argument, which is interpreted differently
      depending on type:

        None or omitted... Build an empty Image_Ref (all fields None).

        string ........... Parse it; see FAQ for syntax. Can be either the
                           standard form (e.g., as in a FROM instruction) or
                           our filename form with percents replacing slashes.

        Lark parse tree .. Must be same result as parsing a string. This
                           allows the parse step to be embedded in a larger
                           parse (e.g., a Dockerfile).

     Warning: References containing a hostname without a dot and no port
     cannot be round-tripped through a string, because the hostname will be
     assumed to be a path component."""

   __slots__ = ("host",
                "port",
                "path",
                "name",
                "tag",
                "digest")

   # Reference parser object. Instantiating a parser took 100ms when we tested
   # it, which means we can't really put it in a loop. But, at parse time,
   # "lark" may refer to a dummy module (see above), so we can't populate the
   # parser here either. We use a class varible and populate it at the time of
   # first use.
   parser = None

   def __init__(self, src=None):
      self.host = None
      self.port = None
      self.path = []
      self.name = None
      self.tag = None
      self.digest = None
      if (isinstance(src, str)):
         src = self.parse(src)
      if (isinstance(src, lark.tree.Tree)):
         self.from_tree(src)
      elif (src is not None):
         assert False, "unsupported initialization type"

   def __str__(self):
      out = ""
      if (self.host is not None):
         out += self.host
      if (self.port is not None):
         out += ":" + str(self.port)
      if (self.host is not None):
         out += "/"
      out += self.path_full
      if (self.tag is not None):
         out += ":" + self.tag
      if (self.digest is not None):
         out += "@sha256:" + self.digest
      return out

   @classmethod
   def parse(class_, s):
      if (class_.parser is None):
         class_.parser = lark.Lark("?start: image_ref\n" + GRAMMAR,
                                   parser="earley", propagate_positions=True)
      if ("%" in s):
         s = s.replace("%", "/")
      hint="https://hpc.github.io/charliecloud/faq.html#how-do-i-specify-an-image-reference"
      try:
         tree = class_.parser.parse(s)
      except lark.exceptions.UnexpectedInput as x:
         if (x.column == -1):
            FATAL("image ref syntax, at end: %s" % s, hint);
         else:
            FATAL("image ref syntax, char %d: %s" % (x.column, s), hint)
      except lark.exceptions.UnexpectedEOF as x:
         # We get UnexpectedEOF because of Lark issue #237. This exception
         # doesn't have a column location.
         FATAL("image ref syntax, at end: %s" % s, hint)
      DEBUG(tree.pretty())
      return tree

   @property
   def as_verbose_str(self):
      def fmt(x):
         if (x is None):
            return None
         else:
            return repr(x)
      return """\
as string:    %s
for filename: %s
fields:
  host    %s
  port    %s
  path    %s
  name    %s
  tag     %s
  digest  %s\
""" % tuple(  [str(self), self.for_path]
            + [fmt(i) for i in (self.host, self.port, self.path,
                                self.name, self.tag, self.digest)])

   @property
   def canonical(self):
      "Copy of self with all the defaults filled in."
      ref = self.copy()
      ref.defaults_add()
      return ref

   @property
   def for_path(self):
      return str(self).replace("/", "%")

   @property
   def path_full(self):
      out = ""
      if (len(self.path) > 0):
         out += "/".join(self.path) + "/"
      out += self.name
      return out

   @property
   def version(self):
      if (self.tag is not None):
         return self.tag
      if (self.digest is not None):
         return "sha256:" + self.digest
      assert False, "version invalid with no tag or digest"

   def copy(self):
      "Return an independent copy of myself."
      return copy.deepcopy(self)

   def defaults_add(self):
      "Set defaults for all empty fields."
      if (self.host is None):
         if ("CH_REGY_DEFAULT_HOST" not in os.environ):
            self.host = "registry-1.docker.io"
         else:
            self.host = os.getenv("CH_REGY_DEFAULT_HOST")
            self.port = int(os.getenv("CH_REGY_DEFAULT_PORT", 443))
            prefix = os.getenv("CH_REGY_PATH_PREFIX")
            if (prefix is not None):
               self.path = prefix.split("/") + self.path
      if (self.port is None): self.port = 443
      if (self.host == "registry-1.docker.io" and len(self.path) == 0):
         # FIXME: For Docker Hub only, images with no path need a path of
         # "library" substituted. Need to understand/document the rules here.
         self.path = ["library"]
      if (self.tag is None and self.digest is None): self.tag = "latest"

   def from_tree(self, t):
      self.host = tree_child_terminal(t, "ir_hostport", "IR_HOST")
      self.port = tree_child_terminal(t, "ir_hostport", "IR_PORT")
      if (self.port is not None):
         self.port = int(self.port)
      self.path = list(tree_child_terminals(t, "ir_path", "IR_PATH_COMPONENT"))
      self.name = tree_child_terminal(t, "ir_name", "IR_PATH_COMPONENT")
      self.tag = tree_child_terminal(t, "ir_tag", "IR_TAG")
      self.digest = tree_child_terminal(t, "ir_digest", "HEX_STRING")
      # Resolve grammar ambiguity for hostnames w/o dot or port.
      if (    self.host is not None
          and "." not in self.host
          and self.port is None):
         self.path.insert(0, self.host)
         self.host = None


class OrderedSet(collections.abc.MutableSet):

   # Note: The superclass provides basic implementations of all the other
   # methods. I didn't evaluate any of these.

   __slots__ = ("data",)

   def __init__(self, others=None):
      self.data = collections.OrderedDict()
      if (others is not None):
         self.data.update((i, None) for i in others)

   def __contains__(self, item):
      return (item in self.data)

   def __iter__(self):
      return iter(self.data.keys())

   def __len__(self):
      return len(self.data)

   def __repr__(self):
      return "%s(%s)" % (self.__class__.__name__, list(iter(self)))

   def add(self, x):
      self.data[x] = None

   def clear(self):
      # Superclass provides an implementation but warns it's slow (and it is).
      self.data.clear()

   def discard(self, x):
      self.data.pop(x, None)


class Path(pathlib.PosixPath):
   """Stock Path objects have the very weird property that appending an
      *absolute* path to an existing path ignores the left operand, leaving
      only the absolute right operand:

        >>> import pathlib
        >>> a = pathlib.Path("/foo/bar")
        >>> a.joinpath("baz")
        PosixPath('/foo/bar/baz')
        >>> a.joinpath("/baz")
        PosixPath('/baz')

      This is contrary to long-standing UNIX/POSIX, where extra slashes in a
      path are ignored, e.g. the path "foo//bar" is equivalent to "foo/bar".
      It seems to be inherited from os.path.join().

      Even with the relatively limited use of Path objects so far, this has
      caused quite a few bugs. IMO it's too difficult and error-prone to
      manually manage whether paths are absolute or relative. Thus, this
      subclass introduces a new operator "//" which does the right thing,
      i.e., if the right operand is absolute, that fact is ignored. E.g.:

        >>> a = Path("/foo/bar")
        >>> a.joinpath_posix("baz")
        Path('/foo/bar/baz')
        >>> a.joinpath_posix("/baz")
        Path('/foo/bar/baz')
        >>> a // "/baz"
        Path('/foo/bar/baz')
        >>> "/baz" // a
        Path('/baz/foo/bar')

      We introduce a new operator because it seemed like too subtle a change
      to the existing operator "/" (which we disable to avoid getting burned
      here in Charliecloud). An alternative was "+" like strings, but that led
      to silently wrong results when the paths *were* strings (components
      concatenated with no slash)."""

   def __floordiv__(self, right):
      return self.joinpath_posix(right)

   def __rfloordiv__(self, left):
      left = Path(left)
      return left.joinpath_posix(self)

   def __truediv__(self, right):
      return NotImplemented

   def __rtruediv__(self, left):
      return NotImplemented

   @property
   def first(self):
      """Return my first component, or if I have no components (i.e.,
         Path(".")), return None."""
      try:
         return self.parts[0]
      except IndexError:
         return None

   def joinpath_posix(self, *others):
      others2 = list()
      for other in others:
         other = Path(other)
         if (other.is_absolute()):
            other = other.relative_to("/")
            assert (not other.is_absolute())
         others2.append(other)
      return self.joinpath(*others2)


class Progress:
   """Simple progress meter for countable things that updates at most once per
      second. Writes first update upon creation. If length is None, then just
      count up (this is for registries like Red Hat that sometimes don't
      provide a Content-Length header for blobs).

      The purpose of the divisor is to allow counting things that are much
      more numerous than what we want to display; for example, to count bytes
      but report MiB, use a divisor of 1048576.

      By default, moves to a new line at first update, then assumes exclusive
      control of this line in the terminal, rewriting the line as needed. If
      output is not a TTY or global log_festoon is set, each update is one log
      entry with no overwriting."""

   __slots__ = ("display_last",
                "divisor",
                "msg",
                "length",
                "unit",
                "overwrite_p",
                "precision",
                "progress")

   def __init__(self, msg, unit, divisor, length):
      self.msg = msg
      self.unit = unit
      self.divisor = divisor
      self.length = length
      if (not os.isatty(log_fp.fileno()) or log_festoon):
         self.overwrite_p = False  # updates all use same line
      else:
         self.overwrite_p = True   # each update on new line
      self.precision = 1 if self.divisor >= 1000 else 0
      self.progress = 0
      self.display_last = float("-inf")
      self.update(0)

   def update(self, increment, last=False):
      now = time.monotonic()
      self.progress += increment
      if (last or now - self.display_last > 1):
         if (self.length is None):
            line = ("%s: %.*f %s"
                    % (self.msg,
                       self.precision, self.progress / self.divisor,
                       self.unit))
         else:
            ct = "%.*f/%.*f" % (self.precision, self.progress / self.divisor,
                                self.precision, self.length / self.divisor)
            pct = "%d%%" % (100 * self.progress / self.length)
            if (ct == "0.0/0.0"):
               # too small, don't print count
               line = "%s: %s" % (self.msg, pct)
            else:
               line = ("%s: %s %s (%s)" % (self.msg, ct, self.unit, pct))
         INFO(line, end=("\r" if self.overwrite_p else "\n"))
         self.display_last = now

   def done(self):
      self.update(0, True)
      if (self.overwrite_p):
         INFO("")  # newline to release display line


class Progress_Reader:
   """Wrapper around a binary file object to maintain a progress meter while
      reading."""

   __slots__ = ("fp",
                "msg",
                "progress")

   def __init__(self, fp, msg):
      self.fp = fp
      self.msg = msg
      self.progress = None

   def __iter__(self):
      return self

   def __next__(self):
      data = self.read(HTTP_CHUNK_SIZE)
      if (len(data) == 0):
         raise StopIteration
      return data

   def close(self):
      if (self.progress is not None):
         self.progress.done()
         ossafe(self.fp.close, "can't close: %s" % self.fp.name)

   def read(self, size=-1):
     data = ossafe(self.fp.read, "can't read: %s" % self.fp.name, size)
     self.progress.update(len(data))
     return data

   def seek(self, *args):
      raise io.UnsupportedOperation

   def start(self):
      # Get file size. This seems awkward, but I wasn't able to find anything
      # better. See: https://stackoverflow.com/questions/283707
      old_pos = self.fp.tell()
      assert (old_pos == 0)  # math will be wrong if this isn't true
      length = self.fp.seek(0, os.SEEK_END)
      self.fp.seek(old_pos)
      self.progress = Progress(self.msg, "MiB", 2**20, length)


class Progress_Writer:
   """Wrapper around a binary file object to maintain a progress meter while
      data are written."""

   __slots__ = ("fp",
                "msg",
                "path",
                "progress")

   def __init__(self, path, msg):
      self.msg = msg
      self.path = path
      self.progress = None

   def close(self):
      if (self.progress is not None):
         self.progress.done()
         ossafe(self.fp.close, "can't close: %s" % self.path)

   def start(self, length):
      self.progress = Progress(self.msg, "MiB", 2**20, length)
      self.fp = open_(self.path, "wb")

   def write(self, data):
      self.progress.update(len(data))
      ossafe(self.fp.write, "can't write: %s" % self.path, data)


class Registry_HTTP:
   """Transfers image data to and from a remote image repository via HTTPS.

      Note that ref refers to the *remote* image. Objects of this class have
      no information about the local image."""

   # Note that with some registries, authentication is required even for
   # anonymous downloads of public images. In this case, we just fetch an
   # authentication token anonymously.

   __slots__ = ("auth",
                "creds",
                "ref",
                "session")

   # https://stackoverflow.com/a/58055668
   class Bearer_Auth(requests.auth.AuthBase):
      __slots__ = ("token",)
      def __init__(self, token):
         self.token = token
      def __call__(self, req):
         req.headers["Authorization"] = "Bearer %s" % self.token
         return req
      def __str__(self):
         return ("Bearer %s" % self.token[:32])

   class Null_Auth(requests.auth.AuthBase):
      def __call__(self, req):
         return req
      def __str__(self):
         return "no authorization"

   def __init__(self, ref):
      # Need an image ref with all the defaults filled in.
      self.ref = ref.canonical
      self.auth = self.Null_Auth()
      self.creds = Credentials()
      self.session = None
      # This is commented out because it prints full request and response
      # bodies to standard output (not stderr), which overwhelms the terminal.
      # Normally, a better debugging approach if you need this is to sniff the
      # connection using e.g. mitmproxy.
      #if (verbose >= 2):
      #   http.client.HTTPConnection.debuglevel = 1

   def _url_of(self, type_, address):
      "Return an appropriate repository URL."
      url_base = "https://%s:%d/v2" % (self.ref.host, self.ref.port)
      return "/".join((url_base, self.ref.path_full, type_, address))

   def authenticate_basic(self, res, auth_d):
      VERBOSE("authenticating using Basic")
      if ("realm" not in auth_d):
         FATAL("WWW-Authenticate missing realm")
      (username, password) = self.creds.get()
      self.auth = requests.auth.HTTPBasicAuth(username, password)

   def authenticate_bearer(self, res, auth_d):
      VERBOSE("authenticating using Bearer")
      # Registries vary in what they put in WWW-Authenticate. Specifically,
      # for everything except NGC, we get back realm, service, and scope. NGC
      # just gives service and scope. We need realm because it's the URL to
      # use for a token. scope also seems critical, so check we have that.
      # Otherwise, just give back all the keys we got.
      for k in ("realm", "scope"):
         if (k not in auth_d):
            FATAL("WWW-Authenticate missing key: %s" % k)
      params = { (k,v) for (k,v) in auth_d.items() if k != "realm" }
      # Request anonymous auth token first, but only for the “safe” methods.
      # We assume no registry will accept anonymous pushes. This is because
      # GitLab registries don't seem to honor the scope argument (issue #975);
      # e.g., for scope “repository:reidpr/foo/00_tiny:pull,push”, GitLab
      # 13.6.3-ee will hand out an anonymous token, but that token is rejected
      # with ‘error="insufficient_scope"’ when the request is re-tried.
      token = None
      if (res.request.method not in ("GET", "HEAD")):
         VERBOSE("won't request anonymous token for %s" % res.request.method)
      else:
         VERBOSE("requesting anonymous auth token")
         res = self.request_raw("GET", auth_d["realm"], {200,401,403},
                                params=params)
         if (res.status_code != 200):
            VERBOSE("anonymous access rejected")
         else:
            token = res.json()["token"]
      # If that failed or was inappropriate, try for an authenticated token.
      if (token is None):
         (username, password) = self.creds.get()
         auth = requests.auth.HTTPBasicAuth(username, password)
         res = self.request_raw("GET", auth_d["realm"], {200}, auth=auth,
                                params=params)
         token = res.json()["token"]
      VERBOSE("received auth token: %s" % (token[:32]))
      self.auth = self.Bearer_Auth(token)

   def authorize(self, res):
      "Authorize using the WWW-Authenticate header in failed response res."
      VERBOSE("authorizing")
      assert (res.status_code == 401)
      # Get authentication instructions.
      if ("WWW-Authenticate" not in res.headers):
         FATAL("WWW-Authenticate header not found")
      auth_h = res.headers["WWW-Authenticate"]
      VERBOSE("WWW-Authenticate raw: %s" % auth_h)
      # Parse the WWW-Authenticate header. Apparently doing this correctly is
      # pretty hard. We use a non-compliant regex kludge [1,2]. Alternatives
      # include putting the grammar into Lark (this can be gotten by reading
      # the RFCs enough) or using the www-authenticate library [3].
      #
      # [1]: https://stackoverflow.com/a/1349528
      # [2]: https://stackoverflow.com/a/1547940
      # [3]: https://pypi.org/project/www-authenticate
      auth_type = auth_h.split()[0]
      auth_d = dict(re.findall(r'(?:(\w+)[:=] ?"?([\w.~:/?#@!$&()*+,;=\'\[\]-]+)"?)+', auth_h))
      VERBOSE("WWW-Authenticate parsed: %s %s" % (auth_type, auth_d))
      # Dispatch to proper method.
      if   (auth_type == "Bearer"):
         self.authenticate_bearer(res, auth_d)
      elif (auth_type == "Basic"):
         self.authenticate_basic(res, auth_d)
      else:
         FATAL("unknown auth type: %s" % auth_h)

   def blob_exists_p(self, digest):
      """Return true if a blob with digest (hex string) exists in the
         remote repository, false otherwise."""
      # Gotchas:
      #
      # 1. HTTP 401 means both unauthorized *or* not found, I assume to avoid
      #    information leakage about the presence of stuff one isn't allowed
      #    to see. By the time it gets here, we should be authenticated, so
      #    interpret it as not found.
      #
      # 2. Sometimes we get 301 Moved Permanently. It doesn't bubble up to
      #    here because requests.request() follows redirects. However,
      #    requests.head() does not follow redirects, and it seems like a
      #    weird status, so I worry there is a gotcha I haven't figured out.
      url = self._url_of("blobs", "sha256:%s" % digest)
      res = self.request("HEAD", url, {200,401,404})
      return (res.status_code == 200)

   def blob_to_file(self, digest, path, msg):
      "GET the blob with hash digest and save it at path."
      # /v2/library/hello-world/blobs/<layer-hash>
      url = self._url_of("blobs", "sha256:" + digest)
      sw = Progress_Writer(path, msg)
      self.request("GET", url, out=sw)
      sw.close()

   def blob_upload(self, digest, data, note=""):
      """Upload blob with hash digest to url. data is the data to upload, and
         can be anything requests can handle; if it's an open file, then it's
         wrapped in a Progress_Reader object. note is a string to prepend to
         the log messages; default empty string."""
      INFO("%s%s: checking if already in repository" % (note, digest[:7]))
      # 1. Check if blob already exists. If so, stop.
      if (self.blob_exists_p(digest)):
         INFO("%s%s: already present" % (note, digest[:7]))
         return
      msg = "%s%s: not present, uploading" % (note, digest[:7])
      if (isinstance(data, io.IOBase)):
         data = Progress_Reader(data, msg)
         data.start()
      else:
         INFO(msg)
      # 2. Get upload URL for blob.
      url = self._url_of("blobs", "uploads/")
      res = self.request("POST", url, {202})
      # 3. Upload blob. We do a "monolithic" upload (i.e., send all the
      # content in a single PUT request) as opposed to a "chunked" upload
      # (i.e., send data in multiple PATCH requests followed by a PUT request
      # with no body).
      url = res.headers["Location"]
      res = self.request("PUT", url, {201}, data=data,
                         params={ "digest": "sha256:%s" % digest })
      if (isinstance(data, Progress_Reader)):
         data.close()
      # 4. Verify blob now exists.
      if (not self.blob_exists_p(digest)):
         FATAL("blob just uploaded does not exist: %s" % digest[:7])

   def close(self):
      if (self.session is not None):
         self.session.close()

   def config_upload(self, config):
      "Upload config (sequence of bytes)."
      self.blob_upload(bytes_hash(config), config, "config: ")

   def fatman_to_file(self, path, msg):
      """GET the manifest for self.image and save it at path. This seems to
         have three possible results:

            1. HTTP 200, and body is a fat manifest: image exists and is
               architecture-aware.

            2. HTTP 200, but body is a skinny manifest: image exists but is
               not architecture-aware.

            3. HTTP 401/404: image does not exist.

         This method raises Not_In_Registry_Error in case 3. The caller is
         responsible for distinguishing cases 1 and 2."""
      url = self._url_of("manifests", self.ref.version)
      pw = Progress_Writer(path, msg)
      # Including TYPES_MANIFEST avoids the server trying to convert its v2
      # manifest to a v1 manifest, which currently fails for images
      # Charliecloud pushes. The error in the test registry is “empty history
      # when trying to create schema1 manifest”.
      accept = "%s;q=0.5" % ",".join(  list(TYPES_INDEX.values())
                                     + list(TYPES_MANIFEST.values()))
      res = self.request("GET", url, out=pw, statuses={200, 401, 404},
                         headers={ "Accept" : accept })
      pw.close()
      if (res.status_code != 200):
         DEBUG(res.content)
         raise Not_In_Registry_Error()

   def layer_from_file(self, digest, path, note=""):
      "Upload gzipped tarball layer at path, which must have hash digest."
      # NOTE: We don't verify the digest b/c that means reading the whole file.
      VERBOSE("layer tarball: %s" % path)
      fp = open_(path, "rb")  # open file avoids reading it all into memory
      self.blob_upload(digest, fp, note)
      ossafe(fp.close, "can't close: %s" % path)

   def manifest_to_file(self, path, msg, digest=None):
      """GET manifest for the image and save it at path. If digest is given,
         use that to fetch the appropriate architecture; otherwise, fetch the
         default manifest using the exising image reference."""
      if (digest is None):
         digest = self.ref.version
      else:
         digest = "sha256:" + digest
      url = self._url_of("manifests", digest)
      pw = Progress_Writer(path, msg)
      accept = "%s;q=0.5" % ",".join(TYPES_MANIFEST.values())
      res = self.request("GET", url, out=pw, statuses={200, 401, 404},
                         headers={ "Accept" : accept })
      pw.close()
      if (res.status_code != 200):
         DEBUG(res.content)
         raise Not_In_Registry_Error()

   def manifest_upload(self, manifest):
      "Upload manifest (sequence of bytes)."
      # Note: The manifest is *not* uploaded as a blob. We just do one PUT.
      INFO("manifest: uploading")
      url = self._url_of("manifests", self.ref.tag)
      self.request("PUT", url, {201}, data=manifest,
                   headers={ "Content-Type": TYPES_MANIFEST["docker2"] })

   def request(self, method, url, statuses={200}, out=None, **kwargs):
      """Request url using method and return the response object. If statuses
         is given, it is set of acceptable response status codes, defaulting
         to {200}; any other response is a fatal error. If out is given,
         response content will be streamed to this Progress_Writer object and
         must be non-zero length.

         Use current session if there is one, or start a new one if not. If
         authentication fails (or isn't initialized), then authenticate and
         re-try the request."""
      self.session_init_maybe()
      VERBOSE("auth: %s" % self.auth)
      if (out is not None):
         kwargs["stream"] = True
      res = self.request_raw(method, url, statuses | {401}, **kwargs)
      if (res.status_code == 401):
         VERBOSE("HTTP 401 unauthorized")
         self.authorize(res)
         VERBOSE("retrying with auth: %s" % self.auth)
         res = self.request_raw(method, url, statuses, **kwargs)
      if (out is not None and res.status_code == 200):
         try:
            length = int(res.headers["Content-Length"])
         except KeyError:
            length = None
         except ValueError:
            FATAL("invalid Content-Length in response")
         out.start(length)
         for chunk in res.iter_content(HTTP_CHUNK_SIZE):
            out.write(chunk)
      return res

   def request_raw(self, method, url, statuses, auth=None, **kwargs):
      """Request url using method. statuses is an iterable of acceptable
         response status codes; any other response is a fatal error. Return
         the requests.Response object.

         Session must already exist. If auth arg given, use it; otherwise, use
         object's stored authentication if initialized; otherwise, use no
         authentication."""
      VERBOSE("%s: %s" % (method, url))
      if (auth is None):
         auth = self.auth
      try:
         res = self.session.request(method, url, auth=auth, **kwargs)
         VERBOSE("response status: %d" % res.status_code)
         if (res.status_code not in statuses):
            FATAL("%s failed; expected status %s but got %d: %s"
                  % (method, statuses, res.status_code, res.reason))
      except requests.exceptions.RequestException as x:
         FATAL("%s failed: %s" % (method, x))
      # Log the rate limit headers if present.
      for h in ("RateLimit-Limit", "RateLimit-Remaining"):
         if (h in res.headers):
            VERBOSE("%s: %s" % (h, res.headers[h]))
      return res

   def session_init_maybe(self):
      "Initialize session if it's not initialized; otherwise do nothing."
      if (self.session is None):
         VERBOSE("initializing session")
         self.session = requests.Session()
         self.session.verify = tls_verify


class Storage:

   """Source of truth for all paths within the storage directory. Do not
      compute any such paths elsewhere!"""

   __slots__ = ("root",)

   def __init__(self, storage_cli):
      self.root = storage_cli
      if (self.root is None):
         self.root = self.root_env()
      if (self.root is None):
         self.root = self.root_default()
      self.root = Path(self.root)

   @property
   def download_cache(self):
      return self.root // "dlcache"

   @property
   def unpack_base(self):
      return self.root // "img"

   @property
   def upload_cache(self):
      return self.root // "ulcache"

   @property
   def valid_p(self):
      # FIXME: require version file too when appropriate (#1147)
      """Return True if storage present and seems valid, False otherwise."""
      return (os.path.isdir(self.unpack_base) and
              os.path.isdir(self.download_cache))

   @property
   def version_file(self):
      return self.root // "version"

   @staticmethod
   def root_default():
      # FIXME: Perhaps we should use getpass.getuser() instead of the $USER
      # environment variable? It seems a lot more robust. But, (1) we'd have
      # to match it in some scripts and (2) it makes the documentation less
      # clear becase we have to explain the fallback behavior.
      return Path("/var/tmp/%s.ch" % user())

   @staticmethod
   def root_env():
      if ("CH_GROW_STORAGE" in os.environ):
         # Avoid surprises if user still has $CH_GROW_STORAGE set (see #906).
         FATAL("$CH_GROW_STORAGE no longer supported; use $CH_IMAGE_STORAGE")
      try:
         return os.environ["CH_IMAGE_STORAGE"]
      except KeyError:
         return None

   def init(self):
      """Ensure the storage directory exists, contains all the appropriate
         top-level directories & metadata, and is the appropriate version."""
      self.init_move_old()  # see issues #1160 and #1243
      if (not os.path.isdir(self.root)):
         op = "initializing"
         v_found = None
      else:
         op = "upgrading"
         if (not self.valid_p):
            if (os.path.exists(self.root) and not listdir(self.root)):
               hint = "let Charliecloud create %s; see FAQ" % self.root.name
            else:
               hint = None
            FATAL("storage directory seems invalid: %s" % self.root, hint=hint)
         if (os.path.isfile(self.version_file)):
            v_found = int(file_read_all(self.version_file))
         else:
            v_found = 1
      if (v_found == STORAGE_VERSION):
         VERBOSE("found storage dir v%d: %s" % (STORAGE_VERSION, self.root))
      elif (v_found in {None, 1}):  # initialize/upgrade
         INFO("%s storage directory: v%d %s" % (op, STORAGE_VERSION, self.root))
         mkdir(self.root)
         mkdir(self.download_cache)
         mkdir(self.unpack_base)
         mkdir(self.upload_cache)
         file_write(self.version_file, "%d\n" % STORAGE_VERSION)
      else:                         # can't upgrade
         FATAL("incompatible storage directory v%d: %s" % (v_found, self.root),
               'you can delete and re-initialize with "ch-image reset"')

   def init_move_old(self):
      """If appropriate, move storage directory from old default path to new.
         See issues #1160 and #1243."""
      old = Storage("/var/tmp/%s/ch-image" % user())
      moves = ( "dlcache", "img", "ulcache", "version" )
      if (self.root != self.root_default()):
         return  # do nothing silently unless using default storage dir
      if (not os.path.exists(old.root)):
         return  # do nothing silently unless old default storage dir exists
      if (not old.valid_p):
         WARNING("storage dir: invalid at old default, ignoring: %s" % old.root)
         return
      INFO("storage dir: valid at old default: %s" % old.root)
      if (not os.path.exists(self.root)):
         mkdir(self.root)
      elif (self.valid_p):
         WARNING("storage dir: also valid at new default: %s" % self.root,
                 hint="consider deleting the old one")
         return
      elif (not os.path.isdir(self.root)):
         return  # new isn't a directory; init/upgrade code will error later
      elif (any(os.path.exists(self.root // i) for i in moves)):
         return  # new is broken; init/upgrade should error later
      # Now we know (1) the old storage exists and is valid and (2) the new
      # storage exists, is a directory, and contains none of the files we'd
      # move. However, it *may* contain subdirectories other parts of
      # Charliecloud care about, e.g. "mnt" for ch-run.
      INFO("storage dir: moving to new default path: %s" % self.root)
      for i in moves:
         src = old.root // i
         dst = self.root // i
         if (os.path.exists(src)):
            DEBUG("moving: %s -> %s" % (src, dst))
            try:
               shutil.move(src, dst)
            except OSError as x:
               FATAL("can't move: %s -> %s: %s"
                     % (x.filename, x.filename2, x.strerror))
      ossafe(os.rmdir, "can't rmdir: %s" % old.root, old.root)
      if (not listdir(old.root.parent)):
         WARNING("parent of old storage dir now empty: %s" % old.root.parent,
                 hint="consider deleting it")

   def manifest_for_download(self, image_ref, digest):
      if (digest is None):
         digest = "skinny"
      return (   self.download_cache
              // ("%s%%%s.manifest.json" % (image_ref.for_path, digest)))

   def fatman_for_download(self, image_ref):
      return self.download_cache // ("%s.fat.json" % image_ref.for_path)

   def reset(self):
      if (self.valid_p):
         rmtree(self.root)
         self.init()  # largely for debugging
      else:
         FATAL("%s not a builder storage" % (self.root));

   def unpack(self, image_ref):
      return self.unpack_base // image_ref.for_path


class TarFile(tarfile.TarFile):

   # This subclass augments tarfile.TarFile to add safety code. While the
   # tarfile module docs [1] say “do not use this class [TarFile] directly”,
   # they also say “[t]he tarfile.open() function is actually a shortcut” to
   # class method TarFile.open(), and the source code recommends subclassing
   # TarFile [2].
   #
   # It's here because the standard library class has problems with symlinks
   # and replacing one file type with another; see issues #819 and #825 as
   # well as multiple unfixed Python bugs [e.g. 3,4,5]. We work around this
   # with manual deletions.
   #
   # [1]: https://docs.python.org/3/library/tarfile.html
   # [2]: https://github.com/python/cpython/blob/2bcd0fe7a5d1a3c3dd99e7e067239a514a780402/Lib/tarfile.py#L2159
   # [3]: https://bugs.python.org/issue35483
   # [4]: https://bugs.python.org/issue19974
   # [5]: https://bugs.python.org/issue23228

   # Need new method name because add() is called recursively and we don't
   # want those internal calls to get our special sauce.
   def add_(self, name, **kwargs):
      kwargs["filter"] = self.fix_member_uidgid
      super().add(name, **kwargs)

   def clobber(self, targetpath, regulars=False, symlinks=False, dirs=False):
      assert (regulars or symlinks or dirs)
      try:
         st = os.lstat(targetpath)
      except FileNotFoundError:
         # We could move this except clause after all the stat.S_IS* calls,
         # but that risks catching FileNotFoundError that came from somewhere
         # other than lstat().
         st = None
      except OSError as x:
         FATAL("can't lstat: %s" % targetpath, targetpath)
      if (st is not None):
         if (stat.S_ISREG(st.st_mode)):
            if (regulars):
               unlink(targetpath)
         elif (stat.S_ISLNK(st.st_mode)):
            if (symlinks):
               unlink(targetpath)
         elif (stat.S_ISDIR(st.st_mode)):
            if (dirs):
               rmtree(targetpath)
         else:
            FATAL("invalid file type 0%o in previous layer; see inode(7): %s"
                  % (stat.S_IFMT(st.st_mode), targetpath))

   @staticmethod
   def fix_link_target(ti, tb):
      """Deal with link (symbolic or hard) weirdness or breakage. If it can be
         fixed, fix it; if not, abort the program."""
      src = Path(ti.name)
      tgt = Path(ti.linkname)
      fix_ct = 0
      # Empty target not allowed; have to check string b/c "" -> Path(".").
      if (len(ti.linkname) == 0):
         FATAL("rejecting link with empty target: %s: %s" % (tb, ti.name))
      # Fix absolute link targets.
      if (tgt.is_absolute()):
         if (ti.issym()):
            # Change symlinks to relative for correct interpretation inside or
            # outside the container.
            kind = "symlink"
            new = (  Path(*(("..",) * (len(src.parts) - 1)))
                   // Path(*(tgt.parts[1:])))
         elif (ti.islnk()):
            # Hard links refer to tar member paths; just strip leading slash.
            kind = "hard link"
            new = tgt.relative_to("/")
         else:
            assert False, "not a link"
         DEBUG("absolute %s: %s -> %s: changing target to: %s"
               % (kind, src, tgt, new))
         tgt = new
         fix_ct = 1
      # Reject links that climb out of image (FIXME: repair instead).
      if (".." in os.path.normpath(src // tgt).split("/")):
         FATAL("rejecting too many up-levels: %s: %s -> %s" % (tb, src, tgt))
      # Done.
      ti.linkname = str(tgt)
      return fix_ct

   @staticmethod
   def fix_member_uidgid(ti):
      assert (ti.name[0] != "/")  # absolute paths unsafe but shouldn't happen
      if (not (ti.isfile() or ti.isdir() or ti.issym() or ti.islnk())):
         FATAL("invalid file type: %s" % ti.name)
      ti.uid = 0
      ti.uname = "root"
      ti.gid = 0
      ti.gname = "root"
      if (ti.mode & stat.S_ISUID):
         VERBOSE("stripping unsafe setuid bit: %s" % ti.name)
         ti.mode &= ~stat.S_ISUID
      if (ti.mode & stat.S_ISGID):
         VERBOSE("stripping unsafe setgid bit: %s" % ti.name)
         ti.mode &= ~stat.S_ISGID
      return ti

   def makedir(self, tarinfo, targetpath):
      # Note: This gets called a lot, e.g. once for each component in the path
      # of the member being extracted.
      TRACE("makedir: %s" % targetpath)
      self.clobber(targetpath, regulars=True, symlinks=True)
      super().makedir(tarinfo, targetpath)

   def makefile(self, tarinfo, targetpath):
      TRACE("makefile: %s" % targetpath)
      self.clobber(targetpath, symlinks=True, dirs=True)
      super().makefile(tarinfo, targetpath)

   def makelink(self, tarinfo, targetpath):
      TRACE("makelink: %s -> %s" % (targetpath, tarinfo.linkname))
      self.clobber(targetpath, regulars=True, symlinks=True, dirs=True)
      super().makelink(tarinfo, targetpath)


## Supporting functions ##

def DEBUG(*args, **kwargs):
   if (verbose >= 2):
      log(*args, color="38;5;6m", **kwargs)  # dark cyan (same as 36m)

def FATAL(*args, **kwargs):
   log(*args, color="1;31m", prefix="error: ", **kwargs)  # bold red
   sys.exit(1)

def INFO(*args, **kwargs):
   "Note: Use print() for output; this function is for logging."
   log(*args, color="33m", **kwargs)  # yellow

def TRACE(*args, **kwargs):
   if (verbose >= 3):
      log(*args, color="38;5;6m", **kwargs)  # dark cyan (same as 36m)

def VERBOSE(*args, **kwargs):
   if (verbose >= 1):
      log(*args, color="38;5;14m", **kwargs)  # light cyan (1;36m but not bold)

def WARNING(*args, **kwargs):
   log(*args, color="31m", prefix="warning: ", **kwargs)  # red

def arch_host_get():
   "Return the registry architecture of the host."
   arch_uname = platform.machine()
   VERBOSE("host architecture from uname: %s" % arch_uname)
   try:
      arch_registry = ARCH_MAP[arch_uname]
   except KeyError:
      FATAL("unknown host architecture: %s" % arch_uname, BUG_REPORT_PLZ)
   VERBOSE("host architecture for registry: %s" % arch_registry)
   return arch_registry

def bytes_hash(data):
   "Return the hash of data, as a hex string with no leading algorithm tag."
   h = hashlib.sha256()
   h.update(data)
   return h.hexdigest()

def ch_run_modify(img, args, env, workdir="/", binds=[], fail_ok=False):
   # Note: If you update these arguments, update the ch-image(1) man page too.
   args = (  [CH_BIN + "/ch-run"]
           + ["-w", "-u0", "-g0", "--no-home", "--no-passwd", "--cd", workdir]
           + sum([["-b", i] for i in binds], [])
           + [img, "--"] + args)
   return cmd(args, env, fail_ok)

def cmd(args, env=None, fail_ok=False):
   VERBOSE("environment: %s" % env)
   VERBOSE("executing: %s" % args)
   cp = subprocess.run(args, env=env, stdin=subprocess.DEVNULL)
   if (not fail_ok and cp.returncode):
      FATAL("command failed with code %d: %s" % (cp.returncode, args[0]))
   return cp.returncode

def color_reset(*fps):
   for fp in fps:
      color_set("0m", fp)

def color_set(color, fp):
   if (fp.isatty()):
      print("\033[" + color, end="", flush=True, file=fp)

def copy2(src, dst, **kwargs):
   "Wrapper for shutil.copy2() with error checking."
   ossafe(shutil.copy2, "can't copy: %s -> %s" % (src, dst), src, dst, **kwargs)

def copytree(*args, **kwargs):
   "Wrapper for shutil.copytree() that exits the program on the first error."
   shutil.copytree(copy_function=copy2, *args, **kwargs)

def dependencies_check():
   """Check more dependencies. If any dependency problems found, here or above
      (e.g., lark module checked at import time), then complain and exit."""
   # enforce Python minimum version
   vsys_py = sys.version_info[:3]  # 4th element is a string
   if (vsys_py < PYTHON_MIN):
      vmin_py_str = ".".join(("%d" % i) for i in PYTHON_MIN)
      vsys_py_str = ".".join(("%d" % i) for i in vsys_py)
      depfails.append(("bad", ("need Python %s but running under %s: %s"
                               % (vmin_py_str, vsys_py_str, sys.executable))))
   # report problems & exit
   for (p, v) in depfails:
      ERROR("%s dependency: %s" % (p, v))
   if (len(depfails) > 0):
      sys.exit(1)

def digest_trim(d):
   """Remove the algorithm tag from digest d and return the rest.

        >>> digest_trim("sha256:foobar")
        'foobar'

      Note: Does not validate the form of the rest."""
   try:
      return d.split(":", maxsplit=1)[1]
   except AttributeError:
      FATAL("not a string: %s" % repr(d))
   except IndexError:
      FATAL("no algorithm tag: %s" % d)

def done_notify():
   if (user() == "jogas"):
      INFO("!!! KOBE !!!")
   else:
      INFO("done")

def file_ensure_exists(path):
   """If the final element of path exists (without dereferencing if it's a
      symlink), do nothing; otherwise, create it as an empty regular file."""
   if (not os.path.lexists(path)):
      fp = open_(path, "w")
      fp.close()

def file_gzip(path, args=[]):
   """Run pigz if it's available, otherwise gzip, on file at path and return
      the file's new name. Pass args to the gzip executable. This lets us gzip
      files (a) in parallel if pigz is installed and (b) without reading them
      into memory."""
   path_c = Path(str(path) + ".gz")
   # On first call, remember first available of pigz and gzip using an
   # attribute of this function (yes, you can do that lol).
   if (not hasattr(file_gzip, "gzip")):
      if (shutil.which("pigz") is not None):
         file_gzip.gzip = "pigz"
      elif (shutil.which("gzip") is not None):
         file_gzip.gzip = "gzip"
      else:
         FATAL("can't find path to gzip or pigz")
   # Remove destination file if it already exists, because gzip --force does
   # several other things too. (Note: pigz sometimes confusingly reports
   # "Inappropriate ioctl for device" if destination already exists.)
   if (os.path.exists(path_c)):
      unlink(path_c)
   # Compress.
   cmd([file_gzip.gzip] + args + [str(path)])
   # Zero out GZIP header timestamp, bytes 4–7 zero-indexed inclusive [1], to
   # ensure layer hash is consistent. See issue #1080.
   # [1]: https://datatracker.ietf.org/doc/html/rfc1952 §2.3.1
   fp = open_(path_c, "r+b")
   ossafe(fp.seek, "can't seek: %s" % fp, 4)
   ossafe(fp.write, "can't write: %s" % fp, b'\x00\x00\x00\x00')
   ossafe(fp.close, "can't close: %s" % fp)
   return path_c

def file_hash(path):
   """Return the hash of data in file at path, as a hex string with no
      algorithm tag. File is read in chunks and can be larger than memory."""
   fp = open_(path, "rb")
   h = hashlib.sha256()
   while True:
      data = ossafe(fp.read, "can't read: %s" % path, 2**18)
      if (len(data) == 0):
         break  # EOF
      h.update(data)
   ossafe(fp.close, "can't close: %s" % path)
   return h.hexdigest()

def file_read_all(path, text=True):
   """Return the contents of file at path, or exit with error. If text, read
      in "rt" mode with UTF-8 encoding; otherwise, read in mode "rb"."""
   if (text):
      mode = "rt"
      encoding = "UTF-8"
   else:
      mode = "rb"
      encoding = None
   fp = open_(path, mode, encoding=encoding)
   data = ossafe(fp.read, "can't read: %s" % path)
   ossafe(fp.close, "can't close: %s" % path)
   return data

def file_size(path, follow_symlinks=False):
   "Return the size of file at path in bytes."
   st = ossafe(os.stat, "can't stat: %s" % path,
               path, follow_symlinks=follow_symlinks)
   return st.st_size

def file_write(path, content, mode=None):
   if (isinstance(content, str)):
      content = content.encode("UTF-8")
   fp = open_(path, "wb")
   ossafe(fp.write, "can't write: %s" % path, content)
   if (mode is not None):
      ossafe(os.chmod, "can't chmod 0%o: %s" % (mode, path))
   ossafe(fp.close, "can't close: %s" % path)

def grep_p(path, rx):
   """Return True if file at path contains a line matching regular expression
      rx, False if it does not."""
   rx = re.compile(rx)
   try:
      with open(path, "rt") as fp:
         for line in fp:
            if (rx.search(line) is not None):
               return True
      return False
   except OSError as x:
      FATAL("error reading %s: %s" % (path, x.strerror))

def init(cli):
   # logging
   global log_festoon, log_fp, verbose
   assert (0 <= cli.verbose <= 3)
   verbose = cli.verbose
   if ("CH_LOG_FESTOON" in os.environ):
      log_festoon = True
   file_ = os.getenv("CH_LOG_FILE")
   if (file_ is not None):
      verbose = max(verbose, 1)
      log_fp = open_(file_, "at")
   atexit.register(color_reset, log_fp)
   VERBOSE("verbose level: %d" % verbose)
   # storage object
   global storage
   storage = Storage(cli.storage)
   # architecture
   global arch, arch_host
   assert (cli.arch is not None)
   arch_host = arch_host_get()
   if (cli.arch == "host"):
      arch = arch_host
   else:
      arch = cli.arch
   # misc
   global password_many, tls_verify
   password_many = cli.password_many
   if (cli.tls_no_verify):
      tls_verify = False
      rpu = requests.packages.urllib3
      rpu.disable_warnings(rpu.exceptions.InsecureRequestWarning)

def json_from_file(path, msg):
   DEBUG("loading JSON: %s: %s" % (msg, path))
   text = file_read_all(path)
   TRACE("text:\n%s" % text)
   try:
      data = json.loads(text)
      DEBUG("result:\n%s" % pprint.pformat(data, indent=2))
   except json.JSONDecodeError as x:
      FATAL("can't parse JSON: %s:%d: %s" % (path, x.lineno, x.msg))
   return data

def listdir(path):
   return ossafe(os.listdir, "can't list: %s" % path, path)

def log(msg, hint=None, color=None, prefix="", end="\n"):
   if (color is not None):
      color_set(color, log_fp)
   if (log_festoon):
      ts = datetime.datetime.now().isoformat(timespec="milliseconds")
      festoon = ("%5d %s  " % (os.getpid(), ts))
   else:
      festoon = ""
   print(festoon, prefix, msg, sep="", file=log_fp, end=end, flush=True)
   if (hint is not None):
      print(festoon, "hint: ", hint, sep="", file=log_fp, flush=True)
   if (color is not None):
      color_reset(log_fp)

def mkdir(path):
   TRACE("ensuring directory: %s" % path)
   try:
      os.mkdir(path)
   except FileExistsError as x:
      if (not os.path.isdir(path)):
         FATAL("can't mkdir: exists and not a directory: %s" % x.filename)
   except OSError as x:
      FATAL("can't mkdir: %s: %s: %s" % (path, x.filename, x.strerror))

def mkdirs(path):
   TRACE("ensuring directories: %s" % path)
   try:
      os.makedirs(path, exist_ok=True)
   except OSError as x:
      FATAL("can't mkdir: %s: %s: %s" % (path, x.filename, x.strerror))

def now_utc_iso8601():
   return datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z"

def open_(path, mode, *args, **kwargs):
   "Error-checking wrapper for open()."
   return ossafe(open, "can't open for %s: %s" % (mode, path),
                 path, mode, *args, **kwargs)

def ossafe(f, msg, *args, **kwargs):
   """Call f with args and kwargs. Catch OSError and other problems and fail
      with a nice error message."""
   try:
      return f(*args, **kwargs)
   except OSError as x:
      FATAL("%s: %s" % (msg, x.strerror))

def prefix_path(prefix, path):
   """"Return True if prefix is a parent directory of path.
       Assume that prefix and path are strings."""
   return prefix == path or (prefix + '/' == path[:len(prefix) + 1])

def rmtree(path):
   if (os.path.isdir(path)):
      TRACE("deleting directory: %s" % path)
      try:
         shutil.rmtree(path)
      except OSError as x:
         FATAL("can't recursively delete directory %s: %s: %s"
               % (path, x.filename, x.strerror))
   else:
      assert False, "unimplemented"

def symlink(target, source, clobber=False):
   if (clobber and os.path.isfile(source)):
      unlink(source)
   try:
      os.symlink(target, source)
   except FileExistsError:
      if (not os.path.islink(source)):
         FATAL("can't symlink: source exists and isn't a symlink: %s" % source)
      if (os.readlink(source) != target):
         FATAL("can't symlink: %s exists; want target %s but existing is %s"
               % (source, target, os.readlink(source)))
   except OSError as x:
      FATAL("can't symlink: %s -> %s: %s" % (source, target, x.strerror))

def tree_child(tree, cname):
   """Locate a descendant subtree named cname using breadth-first search and
      return it. If no such subtree exists, return None."""
   return next(tree_children(tree, cname), None)

def tree_child_terminal(tree, cname, tname, i=0):
   """Locate a descendant subtree named cname using breadth-first search and
      return its first child terminal named tname. If no such subtree exists,
      or it doesn't have such a terminal, return None."""
   st = tree_child(tree, cname)
   if (st is not None):
      return tree_terminal(st, tname, i)
   else:
      return None

def tree_child_terminals(tree, cname, tname):
   """Locate a descendant substree named cname using breadth-first search and
      yield the values of its child terminals named tname. If no such subtree
      exists, or it has no such terminals, yield an empty sequence."""
   for d in tree.iter_subtrees_topdown():
      if (d.data == cname):
         return tree_terminals(d, tname)
   return []

def tree_children(tree, cname):
   "Yield children of tree named cname using breadth-first search."
   for st in tree.iter_subtrees_topdown():
      if (st.data == cname):
         yield st

def tree_terminal(tree, tname, i=0):
   """Return the value of the ith child terminal named tname (zero-based), or
      None if not found."""
   for (j, t) in enumerate(tree_terminals(tree, tname)):
      if (j == i):
         return t
   return None

def tree_terminals(tree, tname):
   """Yield values of all child terminals named tname, or empty list if none
      found."""
   for j in tree.children:
      if (isinstance(j, lark.lexer.Token) and j.type == tname):
         yield j.value

def tree_terminals_cat(tree, tname):
   """Return the concatenated values of all child terminals named tname as a
      string, with no delimiters. If none, return the empty string."""
   return "".join(tree_terminals(tree, tname))

def unlink(path, *args, **kwargs):
   "Error-checking wrapper for os.unlink()."
   ossafe(os.unlink, "can't unlink: %s" % path, path)

def user():
   "Return the current username; exit with error if it can't be obtained."
   try:
      return os.environ["USER"]
   except KeyError:
      FATAL("can't get username: $USER not set")
