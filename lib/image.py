import collections
import copy
import datetime
import json
import os
import re
import sys
import tarfile

import charliecloud as ch
import filesystem as fs


## Hairy Imports ##

# Lark is bundled or provided by package dependencies, so assume it’s always
# importable. There used to be a conflicting package on PyPI called “lark”,
# but it’s gone now [1]. However, verify the version we got.
#
# [1]: https://github.com/lark-parser/lark/issues/505
import lark
LARK_MIN = (0,  7, 1)
LARK_MAX = (99, 0, 0)
lark_version = tuple(int(i) for i in lark.__version__.split("."))
if (not LARK_MIN <= lark_version <= LARK_MAX):
   ch.depfails.append(("bad", 'found Python module "lark" version %d.%d.%d but need between %d.%d.%d and %d.%d.%d inclusive' % (lark_version + LARK_MIN + LARK_MAX)))


## Constants ##

# ARGs that are “magic”: always available, don’t cause cache misses, not saved
# with the image.
ARGS_MAGIC = { "HTTP_PROXY", "HTTPS_PROXY", "FTP_PROXY", "NO_PROXY",
               "http_proxy", "https_proxy", "ftp_proxy", "no_proxy",
               "SSH_AUTH_SOCK", "USER" }
# FIXME: ch.user() not yet defined
ARG_DEFAULTS_MAGIC = { k:v for (k,v) in ((m, os.environ.get(m))
                                          for m in ARGS_MAGIC)
                       if v is not None }

# ARGs with pre-defined default values that *are* saved with the image.
ARG_DEFAULTS = \
   { # calls to chown/fchown withn a user namespace will fail with EINVAL for
     # UID/GIDs besides the current one. This env var tells fakeroot to not
     # try. Credit to Dave Dykstra for pointing us to this.
     "FAKEROOTDONTTRYCHOWN": "1",
     "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
     # GNU tar, when it thinks it’s running as root, tries to chown(2) and
     # chgrp(2) files to whatever is in the tarball.
     "TAR_OPTIONS": "--no-same-owner" }

GRAMMAR_COMMON = r"""
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

IR_PATH_COMPONENT: /[a-z0-9_.-]+/

_string_list: "[" _WS? STRING_QUOTED ( "," _WS? STRING_QUOTED )* _WS? "]"

_WSH: /[ \t]/+                   // sequence of horizontal whitespace
_LINE_CONTINUE: "\\" _WSH? "\n"  // line continuation
_WS: ( _WSH | _LINE_CONTINUE )+  // horizontal whitespace w/ line continuations
_NEWLINES: ( _WSH? "\n" )+       // sequence of newlines

%import common.ESCAPED_STRING -> STRING_QUOTED
"""

# Where the .git “directory” in the image is located. (Normally it’s a
# directory, and that’s what the Git docs call it, but it’s a file for
# worktrees.) We deliberately do not call it “.git” because that makes it
# hidden, but also more importantly it confuses Git into thinking /ch is a
# different Git repo.
GIT_DIR = ch.Path("ch/git")

# Dockerfile grammar. Note image references are not parsed during Dockerfile
# parsing.
GRAMMAR_DOCKERFILE = r"""
start: dockerfile

// First instruction must be ARG or FROM, but that is not a syntax error.
dockerfile: _NEWLINES? ( arg_first | directive | comment )* ( instruction | comment )*

?instruction: _WS? ( arg | copy | env | from_ | label | run | shell | workdir | uns_forever | uns_yet )

directive.2: _WS? "#" _WS? DIRECTIVE_NAME "=" _line _NEWLINES
DIRECTIVE_NAME: ( "escape" | "syntax" )

comment: _WS? _COMMENT_BODY _NEWLINES
_COMMENT_BODY: /#[^\n]*/

arg: "ARG"i _WS ( arg_bare | arg_equals ) _NEWLINES
arg_bare: WORD
arg_equals: WORD "=" ( WORD | STRING_QUOTED )

arg_first.2: "ARG"i _WS ( arg_first_bare | arg_first_equals ) _NEWLINES
arg_first_bare: WORD
arg_first_equals: WORD "=" ( WORD | STRING_QUOTED )

copy: "COPY"i ( _WS option )* _WS ( copy_list | copy_shell ) _NEWLINES
copy_list.2: _string_list
copy_shell: WORD ( _WS WORD )+

env: "ENV"i _WS ( env_space | env_equalses ) _NEWLINES
env_space: WORD _WS _line
env_equalses: env_equals ( _WS env_equals )*
env_equals: WORD "=" ( WORD | STRING_QUOTED )

from_: "FROM"i ( _WS ( option | option_keypair ) )* _WS image_ref [ _WS from_alias ] _NEWLINES
from_alias: "AS"i _WS IR_PATH_COMPONENT  // FIXME: undocumented; this is guess

label: "LABEL"i _WS ( label_space | label_equalses ) _NEWLINES
label_space: WORD _WS _line
label_equalses: label_equals ( _WS label_equals )*
label_equals: WORD "=" ( WORD | STRING_QUOTED )

run: "RUN"i _WS ( run_exec | run_shell ) _NEWLINES
run_exec.2: _string_list
run_shell: _line

shell: "SHELL"i _WS _string_list _NEWLINES

workdir: "WORKDIR"i _WS _line _NEWLINES

uns_forever: UNS_FOREVER _WS _line _NEWLINES
UNS_FOREVER: ( "EXPOSE"i | "HEALTHCHECK"i | "MAINTAINER"i | "STOPSIGNAL"i | "USER"i | "VOLUME"i )

uns_yet: UNS_YET _WS _line _NEWLINES
UNS_YET: ( "ADD"i | "CMD"i | "ENTRYPOINT"i | "ONBUILD"i )

/// Common ///

option: "--" OPTION_KEY "=" OPTION_VALUE
option_keypair: "--" OPTION_KEY "=" OPTION_VAR "=" OPTION_VALUE
OPTION_KEY: /[a-z]+/
OPTION_VALUE: /[^= \t\n]+/
OPTION_VAR: /[a-z]+/

image_ref: IMAGE_REF
IMAGE_REF: /[A-Za-z0-9$:._\/-]+/
""" + GRAMMAR_COMMON

# Grammar for image references.
GRAMMAR_IMAGE_REF = r"""
// Note: Hostnames with no dot and no port get parsed as a hostname, which
// is wrong; it should be the first path component. We patch this error later.
// FIXME: Supposedly this can be fixed with priorities, but I couldn’t get it
// to work with brief trying.

start: image_ref

image_ref: ir_hostport? ir_path? ir_name ( ir_tag | ir_digest )?
ir_hostport: IR_HOST ( ":" IR_PORT )? "/"
ir_path: ( IR_PATH_COMPONENT "/" )+
ir_name: IR_PATH_COMPONENT
ir_tag: ":" IR_TAG
ir_digest: "@sha256:" HEX_STRING
IR_HOST: /[A-Za-z0-9_.-]+/
IR_PORT: /[0-9]+/
IR_TAG: /[A-Za-z0-9_.-]+/
""" + GRAMMAR_COMMON

# Top-level directories we create if not present.
STANDARD_DIRS = { "bin", "dev", "etc", "mnt", "proc", "sys", "tmp", "usr" }


## Classes ##

class Image:
   """Container image object.

      Constructor arguments:

        ref........... Reference object to identify the image.

        unpack_path .. Directory to unpack the image in; if None, infer path
                       in storage dir from ref."""

   __slots__ = ("metadata",
                "ref",
                "unpack_path")

   def __init__(self, ref, unpack_path=None):
      if (isinstance(ref, str)):
         ref = Reference(ref)
      assert isinstance(ref, Reference)
      self.ref = ref
      if (unpack_path is not None):
         assert isinstance(unpack_path, fs.Path)
         self.unpack_path = unpack_path
      else:
         self.unpack_path = ch.storage.unpack(self.ref)
      self.metadata_init()

   @property
   def deleteable(self):
      """True if it’s OK to delete me, either my unpack directory (a) is at
         the expected location within the storage directory xor (b) is not not
         but it looks like an image; False otherwise."""
      if (self.unpack_path == ch.storage.unpack_base // self.unpack_path.name):
         return True
      else:
         if (all(os.path.isdir(self.unpack_path // i)
                for i in ("bin", "dev", "usr"))):
            return True
      return False

   @property
   def last_modified(self):
      # Return the last modified time of self as a datetime.datetime object in
      # the local time zone.
      return datetime.datetime.fromtimestamp(
                 (self.metadata_path // "metadata.json").stat_(False).st_mtime,
                 datetime.timezone.utc).astimezone()

   @property
   def metadata_path(self):
      return self.unpack_path // "ch"

   @property
   def unpack_cache_linked(self):
      return (self.unpack_path // GIT_DIR).exists_()

   @property
   def unpack_exist_p(self):
      return os.path.exists(self.unpack_path)

   def __str__(self):
      return str(self.ref)

   @classmethod
   def glob(class_, image_glob):
      """Return a possibly-empty iterator of images in the storage directory
         matching the given glob."""
      for ref in Reference.glob(image_glob):
         yield class_(ref)

   def commit(self):
      "Commit the current unpack directory into the layer cache."
      assert False, "unimplemented"

   def copy_unpacked(self, other):
      """Copy image other to my unpack directory, which may not exist. other
         can be either a path (string or fs.Path object) or an Image object;
         in the latter case other.unpack_path is used. other need not be a
         valid image; the essentials will be created if needed."""
      if (isinstance(other, str) or isinstance(other, fs.Path)):
         src_path = other
      else:
         src_path = other.unpack_path
      ch.VERBOSE("copying image: %s -> %s" % (src_path, self.unpack_path))
      fs.Path(src_path).copytree(self.unpack_path, symlinks=True)
      # Simpler to copy this file then delete it, rather than filter it out.
      (self.unpack_path // GIT_DIR).unlink_(missing_ok=True)
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
         members we don’t want from this sequence. Thus, we use the OrderedSet
         class defined in this module."""
      TT = collections.namedtuple("TT", ["fp", "members"])
      layers = collections.OrderedDict()
      # Schema version one (v1) allows one or more empty layers for Dockerfile
      # entries like CMD (https://github.com/containers/skopeo/issues/393).
      # Unpacking an empty layer doesn’t accomplish anything, so ignore them.
      empty_cnt = 0
      for (i, path) in enumerate(layer_tars, start=1):
         lh = os.path.basename(path).split(".", 1)[0]
         lh_short = lh[:7]
         ch.INFO("layer %d/%d: %s: listing" % (i, len(layer_tars), lh_short))
         try:
            fp = fs.TarFile.open(path)
            members = ch.OrderedSet(fp.getmembers())  # reads whole file :(
         except tarfile.TarError as x:
            ch.FATAL("cannot open: %s: %s" % (path, x))
         if (lh in layers and len(members) > 0):
            ch.WARNING("ignoring duplicate non-empty layer: %s" % lh_short)
         if (len(members) > 0):
            layers[lh] = TT(fp, members)
         else:
            ch.WARNING("ignoring empty layer: %s" % lh_short)
            empty_cnt += 1
      ch.VERBOSE("skipped %d empty layers" % empty_cnt)
      return layers

   def metadata_init(self):
      "Initialize empty metadata structure."
      # Elsewhere can assume the existence and types of everything here.
      self.metadata = { "arch": ch.arch_host.split("/")[0],  # no variant
                        "arg": { **ARG_DEFAULTS_MAGIC, **ARG_DEFAULTS },
                        "cwd": "/",
                        "env": dict(),
                        "history": list(),
                        "labels": dict(),
                        "shell": ["/bin/sh", "-c"],
                        "volumes": list() }  # set isn’t JSON-serializable

   def metadata_load(self, target_img=None):
      """Load metadata file, replacing the existing metadata object. If
         metadata doesn’t exist, warn and use defaults. If target_img is
         non-None, use that image’s metadata instead of self’s."""
      if (target_img is not None):
         path = target_img.metadata_path
      else:
         path = self.metadata_path
      path //= "metadata.json"
      if (path.exists()):
         ch.VERBOSE("loading metadata")
      else:
         ch.WARNING("no metadata to load; using defaults")
         self.metadata_init()
         return
      self.metadata = path.json_from_file("metadata")
      # upgrade old metadata
      self.metadata.setdefault("arg", dict())
      self.metadata.setdefault("history", list())
      # add default ARG variables
      self.metadata["arg"].update({ **ARG_DEFAULTS_MAGIC, **ARG_DEFAULTS })

   def metadata_merge_from_config(self, config):
      """Interpret all the crap in the config data structure that is
         meaningful to us, and add it to self.metadata. Ignore anything we
         expect in config that’s missing."""
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
         ch.FATAL("config missing key 'config'")
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
               ch.FATAL("can’t parse config: bad Env line: %s" % line)
            self.metadata["env"][k] = v
      # History.
      if ("history" not in config):
         ch.FATAL("invalid config: missing history")
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
         ch.INFO("no config found; initializing empty metadata")
      else:
         # Copy pulled config file into the image so we still have it.
         path = self.metadata_path // "config.pulled.json"
         config_json.copy(path)
         ch.VERBOSE("pulled config path: %s" % path)
         self.metadata_merge_from_config(path.json_from_file("config"))
      self.metadata_save()

   def metadata_save(self):
      """Dump image’s metadata to disk, including the main data structure but
         also all auxiliary files, e.g. ch/environment."""
      # Adjust since we don’t save everything.
      metadata = copy.deepcopy(self.metadata)
      for k in ARGS_MAGIC:
         metadata["arg"].pop(k, None)
      # Serialize. We take care to pretty-print this so it can (sometimes) be
      # parsed by simple things like grep and sed.
      out = json.dumps(metadata, indent=2, sort_keys=True)
      ch.DEBUG("metadata:\n%s" % out)
      # Main metadata file.
      path = self.metadata_path // "metadata.json"
      ch.VERBOSE("writing metadata file: %s" % path)
      path.file_write(out + "\n")
      # /ch/environment
      path = self.metadata_path // "environment"
      ch.VERBOSE("writing environment file: %s" % path)
      path.file_write( (  "\n".join("%s=%s" % (k,v) for (k,v)
                                    in sorted(metadata["env"].items()))
                        + "\n"))
      # mkdir volumes
      ch.VERBOSE("ensuring volume directories exist")
      for path in metadata["volumes"]:
         (self.unpack_path // path).mkdirs()

   def tarballs_write(self, tarball_dir):
      """Write one uncompressed tarball per layer to tarball_dir. Return a
         sequence of tarball basenames, with the lowest layer first."""
      # FIXME: Yes, there is only one layer for now and we’ll need to update
      # it when (if) we have multiple layers. But, I wanted the interface to
      # support multiple layers.
      base = "%s.tar" % self.ref.for_path
      path = tarball_dir // base
      try:
         ch.INFO("layer 1/1: gathering")
         ch.VERBOSE("writing tarball: %s" % path)
         fp = fs.TarFile.open(path, "w", format=tarfile.PAX_FORMAT)
         unpack_path = self.unpack_path.resolve()  # aliases use symlinks
         ch.VERBOSE("canonicalized unpack path: %s" % unpack_path)
         fp.add_(unpack_path, arcname=".")
         fp.close()
      except OSError as x:
         ch.FATAL("can’t write tarball: %s" % x.strerror)
      return [base]

   def unpack(self, layer_tars, last_layer=None):
      """Unpack config_json (path to JSON config file) and layer_tars
         (sequence of paths to tarballs, with lowest layer first) into the
         unpack directory, validating layer contents and dealing with
         whiteouts. Empty layers are ignored. The unpack directory must not
         exist."""
      if (last_layer is None):
         last_layer = sys.maxsize
      ch.INFO("flattening image")
      self.unpack_layers(layer_tars, last_layer)
      self.unpack_init()

   def unpack_cache_unlink(self):
      (self.unpack_path // ".git").unlink()

   def unpack_clear(self):
      """If the unpack directory does not exist, do nothing. If the unpack
         directory is already an image, remove it. Otherwise, error."""
      if (not os.path.exists(self.unpack_path)):
         ch.VERBOSE("no image found: %s" % self.unpack_path)
      else:
         if (not os.path.isdir(self.unpack_path)):
            ch.FATAL("can’t flatten: %s exists but is not a directory"
                  % self.unpack_path)
         if (not self.deleteable):
            ch.FATAL("can’t flatten: %s exists but does not appear to be an image"
                     % self.unpack_path)
         ch.VERBOSE("removing image: %s" % self.unpack_path)
         t = ch.Timer()
         self.unpack_path.rmtree()
         t.log("removed image")

   def unpack_delete(self):
      ch.VERBOSE("unpack path: %s" % self.unpack_path)
      if (not self.unpack_exist_p):
         ch.FATAL("image not found, can’t delete: %s" % self.ref)
      if (self.deleteable):
         ch.INFO("deleting image: %s" % self.ref)
         self.unpack_path.chmod_min()
         for (dir_, subdirs, _) in os.walk(self.unpack_path):
            # must fix as subdirs so we can traverse into them
            for subdir in subdirs:
               (fs.Path(dir_) // subdir).chmod_min()
         self.unpack_path.rmtree()
      else:
         ch.FATAL("storage directory seems broken: not an image: %s" % self.ref)

   def unpack_init(self):
      """Initialize the unpack directory, which must exist. Any setup already
         present will be left unchanged. After this, self.unpack_path is a
         valid Charliecloud image directory."""
      # Metadata directory.
      (self.unpack_path // "ch").mkdir_()
      (self.unpack_path // "ch/environment").file_ensure_exists()
      # Essential directories & mount points. Do nothing if something already
      # exists, without dereferencing, in case it’s a symlink, which will work
      # for bind-mount later but won’t resolve correctly now outside the
      # container (e.g. linuxcontainers.org images; issue #1015).
      #
      # WARNING: Keep in sync with shell scripts.
      for d in list(STANDARD_DIRS) + ["mnt/%d" % i for i in range(10)]:
         d = self.unpack_path // d
         if (not os.path.lexists(d)):
            d.mkdirs()
      (self.unpack_path // "etc/hosts").file_ensure_exists()
      (self.unpack_path // "etc/resolv.conf").file_ensure_exists()

   def unpack_layers(self, layer_tars, last_layer):
      layers = self.layers_open(layer_tars)
      self.validate_members(layers)
      self.whiteouts_resolve(layers)
      self.unpack_path.mkdir_()  # create directory in case no layers
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         lh_short = lh[:7]
         if (i > last_layer):
            ch.INFO("layer %d/%d: %s: skipping per --last-layer"
                 % (i, len(layers), lh_short))
         else:
            ch.INFO("layer %d/%d: %s: extracting" % (i, len(layers), lh_short))
            try:
               fp.extractall(path=self.unpack_path, members=members)
            except OSError as x:
               ch.FATAL("can’t extract layer %d: %s" % (i, x.strerror))

   def validate_members(self, layers):
      ch.INFO("validating tarball members")
      top_dirs = set()
      ch.VERBOSE("pass 1: canonicalizing member paths")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         abs_ct = 0
         for m in list(members):   # copy b/c we remove items from the set
            # Remove members with empty paths.
            if (len(m.name) == 0):
               ch.WARNING("layer %d/%d: %s: skipping member with empty path"
                       % (i, len(layers), lh[:7]))
               members.remove(m)
            # Convert member paths to fs.Path objects for easier processing.
            # Note: In my testing, parsing a string into a fs.Path object took
            # about 2.5µs, so this should be plenty fast.
            m.name = fs.Path(m.name)
            # Reject members with up-levels.
            if (".." in m.name.parts):
               ch.FATAL("rejecting up-level member: %s: %s" % (fp.name, m.name))
            # Correct absolute paths.
            if (m.name.is_absolute()):
               m.name = m.name.relative_to("/")
            # Record top-level directory.
            if (len(m.name.parts) > 1 or m.isdir()):
               top_dirs.add(m.name.first)
         if (abs_ct > 0):
            ch.WARNING("layer %d/%d: %s: fixed %d absolute member paths"
                    % (i, len(layers), lh[:7], abs_ct))
      top_dirs.discard(None)  # ignore “.”
      # Convert to tarbomb if (1) there is a single enclosing directory and
      # (2) that directory is not one of the standard directories, e.g. to
      # allow images containing just “/bin/fooprog”.
      if (len(top_dirs) != 1 or not top_dirs.isdisjoint(STANDARD_DIRS)):
         ch.VERBOSE("pass 2: conversion to tarbomb not needed")
      else:
         ch.VERBOSE("pass 2: converting to tarbomb")
         for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
            for m in members:
               if (len(m.name.parts) > 0):  # ignore “.”
                  m.name = fs.Path(*m.name.parts[1:])  # strip first component
      ch.VERBOSE("pass 3: analyzing members")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         dev_ct = 0
         link_fix_ct = 0
         for m in list(members):  # copy again
            m.name = str(m.name)  # other code assumes strings
            if (m.isdev()):
               # Device or FIFO: Ignore.
               dev_ct += 1
               ch.VERBOSE("ignoring device file: %s" % m.name)
               members.remove(m)
               continue
            elif (m.issym() or m.islnk()):
               link_fix_ct += fs.TarFile.fix_link_target(m, fp.name)
            elif (m.isdir()):
               # Directory: Fix bad permissions (hello, Red Hat).
               m.mode |= 0o700
            elif (m.isfile()):
               # Regular file: Fix bad permissions (HELLO RED HAT!!).
               m.mode |= 0o600
            else:
               ch.FATAL("unknown member type: %s" % m.name)
            # Discard Git metadata (files that begin with “.git”).
            if (re.search(r"^(\./)?\.git", m.name)):
               ch.WARNING("ignoring member: %s" % m.name)
               members.remove(m)
               continue
            # Discard anything under /dev. Docker puts regular files and
            # directories in here on “docker export”. Note leading slashes
            # already taken care of in TarFile.fix_member_path() above.
            if (re.search(r"^(\./)?dev/.", m.name)):
               ch.VERBOSE("ignoring member under /dev: %s" % m.name)
               members.remove(m)
               continue
            fs.TarFile.fix_member_uidgid(m)
         if (dev_ct > 0):
            ch.WARNING("layer %d/%d: %s: ignored %d devices and/or FIFOs"
                    % (i, len(layers), lh[:7], dev_ct))
         if (link_fix_ct > 0):
            ch.INFO("layer %d/%d: %s: changed %d absolute symbolic and/or hard links to relative"
                    % (i, len(layers), lh[:7], link_fix_ct))

   def whiteout_rm_prefix(self, layers, max_i, prefix):
      """Ignore members of all layers from 1 to max_i inclusive that have path
         prefix of prefix. For example, if prefix is foo/bar, then ignore
         foo/bar and foo/bar/baz but not foo/barbaz. Return count of members
         ignored."""
      ch.TRACE("finding members with prefix: %s" % prefix)
      prefix = os.path.normpath(prefix)  # "./foo" == "foo"
      ignore_ct = 0
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         if (i > max_i): break
         members2 = list(members)  # copy b/c we’ll alter members
         for m in members2:
            if (ch.prefix_path(prefix, m.name)):
               ignore_ct += 1
               members.remove(m)
               ch.TRACE("layer %d/%d: %s: ignoring %s"
                     % (i, len(layers), lh[:7], m.name))
      return ignore_ct

   def whiteouts_resolve(self, layers):
      """Resolve whiteouts. See:
         https://github.com/opencontainers/image-spec/blob/master/layer.md"""
      ch.INFO("resolving whiteouts")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         wo_ct = 0
         ig_ct = 0
         members2 = list(members)  # copy b/c we’ll alter members
         for m in members2:
            dir_ = os.path.dirname(m.name)
            filename = os.path.basename(m.name)
            if (filename.startswith(".wh.")):
               wo_ct += 1
               members.remove(m)
               if (filename == ".wh..wh..opq"):
                  # “Opaque whiteout”: remove contents of dir_.
                  ch.DEBUG("found opaque whiteout: %s" % m.name)
                  ig_ct += self.whiteout_rm_prefix(layers, i - 1, dir_)
               else:
                  # “Explicit whiteout”: remove same-name file without ".wh.".
                  ch.DEBUG("found explicit whiteout: %s" % m.name)
                  ig_ct += self.whiteout_rm_prefix(layers, i - 1,
                                                   dir_ + "/" + filename[4:])
         if (wo_ct > 0):
            ch.VERBOSE("layer %d/%d: %s: %d whiteouts; %d members ignored"
                    % (i, len(layers), lh[:7], wo_ct, ig_ct))


class Reference:
   """Reference to an image in a remote repository.

      The constructor takes one argument, which is interpreted differently
      depending on type:

        None or omitted... Build an empty Reference (all fields None).

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
                "digest",
                "variables")

   # Reference parser object. Instantiating a parser took 100ms when we tested
   # it, which means we can’t really put it in a loop. But, at parse time,
   # “lark” may refer to a dummy module (see above), so we can’t populate the
   # parser here either. We use a class varible and populate it at the time of
   # first use.
   parser = None

   def __init__(self, src=None, variables=None):
      self.host = None
      self.port = None
      self.path = []
      self.name = None
      self.tag = None
      self.digest = None
      self.variables = dict() if variables is None else variables
      if (isinstance(src, str)):
         src = self.parse(src, self.variables)
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

   @staticmethod
   def path_to_ref(path):
      if (isinstance(path, fs.Path)):
         path = path.name
      return path.replace("+", ":").replace("%", "/")

   @staticmethod
   def ref_to_pathstr(ref_str):
      return ref_str.replace("/", "%").replace(":", "+")

   @classmethod
   def glob(class_, image_glob):
      """Return a possibly-empty iterator of references in the storage
         directory matching the given glob."""
      for path in ch.storage.unpack_base.glob(class_.ref_to_pathstr(image_glob)):
         yield class_(class_.path_to_ref(path))

   @classmethod
   def parse(class_, s, variables):
      if (class_.parser is None):
         class_.parser = lark.Lark(GRAMMAR_IMAGE_REF, parser="earley",
                                   propagate_positions=True, tree_class=Tree)
      s = s.translate(str.maketrans("%+", "/:", "&"))
      hint="https://hpc.github.io/charliecloud/faq.html#how-do-i-specify-an-image-reference"
      s = ch.variables_sub(s, variables)
      if "$" in s:
         ch.FATAL("image reference contains an undefined variable: %s" % s)
      try:
         tree = class_.parser.parse(s)
      except lark.exceptions.UnexpectedInput as x:
         if (x.column == -1):
            ch.FATAL("image ref syntax, at end: %s" % s, hint);
         else:
            ch.FATAL("image ref syntax, char %d: %s" % (x.column, s), hint)
      except lark.exceptions.UnexpectedEOF as x:
         # We get UnexpectedEOF because of Lark issue #237. This exception
         # doesn’t have a column location.
         ch.FATAL("image ref syntax, at end: %s" % s, hint)
      ch.DEBUG(tree.pretty())
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
      return self.ref_to_pathstr(str(self))

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
         # “library” substituted. Need to understand/document the rules here.
         self.path = ["library"]
      if (self.tag is None and self.digest is None): self.tag = "latest"

   def from_tree(self, t):
      self.host = t.child_terminal("ir_hostport", "IR_HOST")
      self.port = t.child_terminal("ir_hostport", "IR_PORT")
      if (self.port is not None):
         self.port = int(self.port)
      self.path = [    ch.variables_sub(s, self.variables)
                   for s in t.child_terminals("ir_path", "IR_PATH_COMPONENT")]
      self.name = t.child_terminal("ir_name", "IR_PATH_COMPONENT")
      self.tag = t.child_terminal("ir_tag", "IR_TAG")
      self.digest = t.child_terminal("ir_digest", "HEX_STRING")
      for a in ("host", "port", "name", "tag", "digest"):
         setattr(self, a, ch.variables_sub(getattr(self, a), self.variables))
      # Resolve grammar ambiguity for hostnames w/o dot or port.
      if (    self.host is not None
          and "." not in self.host
          and self.port is None):
         self.path.insert(0, self.host)
         self.host = None


class Tree(lark.tree.Tree):

   def child(self, cname):
      """Locate a descendant subtree named cname using breadth-first search
         and return it. If no such subtree exists, return None."""
      return next(self.children_(cname), None)

   def child_terminal(self, cname, tname, i=0):
      """Locate a descendant subtree named cname using breadth-first search
         and return its first child terminal named tname. If no such subtree
         exists, or it doesn’t have such a terminal, return None."""
      st = self.child(cname)
      if (st is not None):
         return st.terminal(tname, i)
      else:
         return None

   def child_terminals(self, cname, tname):
      """Locate a descendant substree named cname using breadth-first search
         and yield the values of its child terminals named tname. If no such
         subtree exists, or it has no such terminals, yield empty sequence."""
      for d in self.iter_subtrees_topdown():
         if (d.data == cname):
            return d.terminals(tname)
      return []

   def child_terminals_cat(self, cname, tname):
      """Return the concatenated values of all child terminals named tname as
         a string, with no delimiters. If none, return the empty string."""
      return "".join(self.child_terminals(cname, tname))

   def children_(self, cname):
      "Yield children of tree named cname using breadth-first search."
      for st in self.iter_subtrees_topdown():
         if (st.data == cname):
            yield st

   def iter_subtrees_topdown(self, *args, **kwargs):
      return super().iter_subtrees_topdown(*args, **kwargs)

   def terminal(self, tname, i=0):
      """Return the value of the ith child terminal named tname (zero-based),
         or None if not found."""
      for (j, t) in enumerate(self.terminals(tname)):
         if (j == i):
            return t
      return None

   def terminals(self, tname):
      """Yield values of all child terminals named tname, or empty list if
         none found."""
      for j in self.children:
         if (isinstance(j, lark.lexer.Token) and j.type == tname):
            yield j.value

   def terminals_cat(self, tname):
      """Return the concatenated values of all child terminals named tname as
         a string, with no delimiters. If none, return the empty string."""
      return "".join(self.terminals(tname))
