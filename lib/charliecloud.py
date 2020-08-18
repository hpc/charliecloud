import argparse
import atexit
import collections
import copy
import datetime
import http.client
import json
import os
import getpass
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import types

import version


## Imports not in standard library ##

# These are messy because we need --version and --help even if a dependency is
# missing. Among other things, nothing can depend on non-standard modules at
# parse time.

# List of dependency problems.
depfails = []

try:
   # Lark is additionally messy because there are two packages on PyPI that
   # provide a "lark" module.
   import lark   # ImportError if no such module
   lark.Visitor  # AttributeError if wrong module
except (ImportError, AttributeError) as x:
   if (isinstance(x, ImportError)):
      depfails.append(("missing", 'Python module "lark-parser"'))
   elif (isinstance(x, AttributeError)):
      depfails.append(("bad", 'found Python module "lark"; need "lark-parser"'))
   else:
      assert False
   # Mock up a lark module so the rest of the file parses.
   lark = types.ModuleType("lark")
   lark.Visitor = object

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


## Globals ##

# Logging; set using log_setup() below.
verbose = 0          # Verbosity level. Can be 0, 1, or 2.
log_festoon = False  # If true, prepend pid and timestamp to chatter.
log_fp = sys.stderr  # File object to print logs to.

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

?instruction: _WS? ( arg | copy | env | from_ | run | workdir | uns_forever | uns_yet )

directive.2: _WS? "#" _WS? DIRECTIVE_NAME "=" LINE _NEWLINES
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
env_space: WORD _WS LINE
env_equalses: env_equals ( _WS env_equals )*
env_equals: WORD "=" ( WORD | STRING_QUOTED )

from_: "FROM"i ( _WS option )* _WS image_ref [ _WS from_alias ] _NEWLINES
from_alias: "AS"i _WS IR_PATH_COMPONENT  // FIXME: undocumented; this is guess

run: "RUN"i _WS ( run_exec | run_shell ) _NEWLINES
run_exec.2: _string_list
run_shell: LINE

workdir: "WORKDIR"i _WS LINE _NEWLINES

uns_forever: UNS_FOREVER _WS LINE _NEWLINES
UNS_FOREVER: ( "EXPOSE"i | "HEALTHCHECK"i | "MAINTAINER"i | "STOPSIGNAL"i | "USER"i | "VOLUME"i )

uns_yet: UNS_YET _WS LINE _NEWLINES
UNS_YET: ( "ADD"i | "CMD"i | "ENTRYPOINT"i | "LABEL"i | "ONBUILD"i | "SHELL"i )

/// Common ///

option: "--" OPTION_KEY "=" OPTION_VALUE
OPTION_KEY: /[a-z]+/
OPTION_VALUE: /[^ \t\n]+/

HEX_STRING: /[0-9A-Fa-f]+/
LINE: ( LINE_CONTINUE | /[^\n]/ )+
WORD: /[^ \t\n=]/+

_string_list: "[" _WS? STRING_QUOTED ( "," _WS? STRING_QUOTED )* _WS? "]"

LINE_CONTINUE: "\\\n"
%ignore LINE_CONTINUE

_NEWLINES: _WS? "\n"+
_WS: /[ \t]/+

%import common.ESCAPED_STRING -> STRING_QUOTED
"""


## Classes ##

class CLI_Action_Exit(argparse.Action):

   def __init__(self, *args, **kwargs):
      super().__init__(nargs=0, *args, **kwargs)

class CLI_Dependencies(CLI_Action_Exit):

   def __call__(self, *args, **kwargs):
      dependencies_check()
      sys.exit(0)

class CLI_Version(CLI_Action_Exit):

   def __call__(self, *args, **kwargs):
      print(version.VERSION)
      sys.exit(0)

class Image:
   """Container image object.

      Constructor arguments:

        ref.............. Image_Ref object to identify the image.

        download_cache .. Directory containing the download cache; this is
                          where layers and manifests go. If None,
                          download-related operations will not be available.

        unpack_dir ...... Directory containing unpacked images.

        image_subdir .... Subdirectory of unpack_dir to put unpacked image in.
                          If None, infer from id; if the empty string,
                          unpack_dir will be used directly."""

   __slots__ = ("ref",
                "download_cache",
                "image_subdir",
                "layer_hashes",
                "schema_version",
                "unpack_dir")

   def __init__(self, ref, download_cache, unpack_dir, image_subdir=None):
      assert isinstance(ref, Image_Ref)
      self.ref = ref
      self.download_cache = download_cache
      self.unpack_dir = unpack_dir
      if (image_subdir is None):
         self.image_subdir = self.ref.for_path
      else:
         self.image_subdir = image_subdir
      self.layer_hashes = None
      self.schema_version = None

   def __str__(self):
      return str(self.ref)

   @property
   def unpack_path(self):
      "Path to the directory containing the image."
      return "%s/%s" % (self.unpack_dir, self.image_subdir)

   @property
   def manifest_path(self):
      "Path to the manifest file."
      return "%s/%s.manifest.json" % (self.download_cache, self.ref.for_path)

   def commit(self):
      "Commit the current unpack directory into the layer cache."
      assert False, "unimplemented"

   def copy_unpacked(self, other):
      "Copy the unpack directory of Image other to my unpack directory."
      DEBUG("copying image: %s -> %s" % (other.unpack_path, self.unpack_path))
      self.unpack_create_ok()
      copytree(other.unpack_path, self.unpack_path, symlinks=True)

   def download(self, use_cache):
      """Download image manifest and layers according to origin and put them
         in the download cache. By default, any components already in the
         cache are skipped; if use_cache is False, download them anyway,
         overwriting what's in the cache."""
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      dl = Repo_Downloader(self.ref)
      DEBUG("downloading image: %s" % dl.ref)
      mkdirs(self.download_cache)
      # manifest
      if (os.path.exists(self.manifest_path) and use_cache):
         INFO("manifest: using existing file")
      else:
         INFO("manifest: downloading")
         dl.get_manifest(self.manifest_path)
      # layers
      self.layer_hashes_load()
      for (i, lh) in enumerate(self.layer_hashes, start=1):
         path = self.layer_path(lh)
         DEBUG("layer path: %s" % path)
         INFO("layer %d/%d: %s: " % (i, len(self.layer_hashes), lh[:7]), end="")
         if (os.path.exists(path) and use_cache):
            INFO("using existing file")
         else:
            INFO("downloading")
            dl.get_layer(lh, path)
      dl.close()

   def fixup(self):
      "Add the Charliecloud workarounds to the unpacked image."
      DEBUG("fixing up image: %s" % self.unpack_path)
      # Metadata directory.
      mkdirs("%s/ch/bin" % self.unpack_path)
      file_ensure_exists("%s/ch/environment" % self.unpack_path)
      # Mount points.
      file_ensure_exists("%s/etc/hosts" % self.unpack_path)
      file_ensure_exists("%s/etc/resolv.conf" % self.unpack_path)
      # /etc/{passwd,group}
      file_write("%s/etc/passwd" % self.unpack_path, """\
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:nobody:/:/bin/false
""")
      file_write("%s/etc/group" % self.unpack_path, """\
root:x:0:
nogroup:x:65534:
""")
      # Kludges to work around expectations of real root, not UID 0 in a
      # unprivileged user namespace. See also the default environment.
      #
      # Debian "apt" and friends want to chown(1), chgrp(1), etc.
      symlink("/bin/true", "%s/ch/bin/chown" % self.unpack_path)
      symlink("/bin/true", "%s/ch/bin/chgrp" % self.unpack_path)
      symlink("/bin/true", "%s/ch/bin/dpkg-statoverride" % self.unpack_path)

   def flatten(self):
      "Flatten the layers in the download cache into the unpack directory."
      layers = self.layers_read()
      self.validate_members(layers)
      self.whiteouts_resolve(layers)
      INFO("flattening image")
      self.unpack_create()
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         INFO("layer %d/%d: %s: extracting" % (i, len(layers), lh[:7]))
         try:
            fp.extractall(path=self.unpack_path, members=members)
         except OSError as x:
            FATAL("can't extract layer %d: %s" % (i, x.strerror))

   def layer_hashes_load(self):
      "Load the layer hashes from the manifest file."
      try:
         fp = open_(self.manifest_path, "rt", encoding="UTF-8")
      except OSError as x:
         FATAL("can't open manifest file: %s: %s"
               % (self.manifest_path, x.strerror))
      try:
         doc = json.load(fp)
      except json.JSONDecodeError as x:
         FATAL("can't parse manifest file: %s:%d %s"
               % (self.manifest_path, x.lineno, x.msg))

      self.schema_version = doc['schemaVersion']
      if self.schema_version == 1:
         DEBUG('using schema version one (1) manifest')
         try:
            self.layer_hashes = [i["blobSum"].split(":")[1] for i in doc["fsLayers"]]
         except (AttributeError, KeyError, IndexError):
            FATAL("can't parse manifest file: %s" % self.manifest_path)
      elif self.schema_version == 2:
         DEBUG('using schema version two (2) manifest')
         try:
            self.layer_hashes = [i["digest"].split(":")[1] for i in doc["layers"]]
         except (AttributeError, KeyError, IndexError):
            FATAL("can't parse manifest file: %s" % self.manifest_path)
      else:
         FATAL("unrecognized manifest schema version: 'schemaVersion' :%s"
               % self.schema_version)

   def layer_path(self, layer_hash):
      "Return the path to tarball for layer layer_hash."
      return "%s/%s.tar.gz" % (self.download_cache, layer_hash)

   def layers_read(self):
      """Open the layer tarballs and read some metadata. Return an OrderedDict
         with the lowest layer first; key is hash string, value is namedtuple
         with fields fp, the open TarFile object, and members, an OrderedDict
         of members obtained from fp.getmembers() (key TarInfo object, value
         None).

         We use an OrderedDict for members because tarballs are a stream
         format with very poor random access performance. Under the hood,
         TarFile.extractall() extracts the members in the order they are
         specified. Thus, we need to preserve the order given by getmembers()
         while also making it fast to remove members we don't want to
         extract, which rules out retaining them as a list.

         FIXME: Once we get to Python 3.7, we should just use plain dict."""
      TT = collections.namedtuple("TT", ["fp", "members"])
      if (self.layer_hashes is None):
         self.layer_hashes_load()
      layers = collections.OrderedDict()
      if self.schema_version == 1:
         layers = layers.OrderedDict(reversed(list(layers.items())))
      for (i, lh) in enumerate(self.layer_hashes, start=1):
         INFO("layer %d/%d: %s: listing" % (i, len(self.layer_hashes), lh[:7]))
         path = self.layer_path(lh)
         try:
            fp = TarFile.open(path)
            members_list = fp.getmembers()  # reads whole file :(
         except tarfile.TarError as x:
            FATAL("cannot open: %s: %s" % (path, x))
         members = collections.OrderedDict([(m, None) for m in members_list])
         layers[lh] = TT(fp, members)
      return layers

   def pull_to_unpacked(self, use_cache=True, fixup=False):
      """Pull and flatten image. If fixup, then also add the Charliecloud
         workarounds to the image directory."""
      self.download(use_cache)
      self.flatten()
      if (fixup):
         self.fixup()

   def validate_members(self, layers):
      INFO("validating tarball members")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         dev_ct = 0
         members2 = list(members.keys())  # copy b/c we'll alter members
         for m in members2:
            self.validate_tar_path(self.layer_path(lh), m.name)
            if (m.isdev()):
               # Device or FIFO: Ignore.
               dev_ct += 1
               del members[m]
            if (m.islnk()):
               # Hard link: Fail if pointing outside top level. (Note that we
               # let symlinks point wherever they want, because they aren't
               # interpreted until run time in a container.)
               self.validate_tar_link(self.layer_path(lh), m.name, m.linkname)
            if (m.isdir()):
               # Fix bad directory permissions (hello, Red Hat).
               m.mode |= 0o700
            if (m.isfile()):
               # Fix bad file permissions (HELLO RED HAT!!).
               m.mode |= 0o600
         if (dev_ct > 0):
            INFO("layer %d/%d: %s: ignored %d devices and/or FIFOs"
                 % (i, len(layers), lh[:7], dev_ct))

   def validate_tar_path(self, filename, path):
      "Reject paths outside the tar top level by aborting the program."
      if (len(path) > 0 and path[0] == "/"):
         FATAL("rejecting absolute path: %s: %s" % (filename, path))
      if (".." in path.split("/")):
         FATAL("rejecting path with up-level: %s: %s" % (filename, path))

   def validate_tar_link(self, filename, path, target):
      """Reject hard link targets outside the tar top level by aborting the
         program."""
      self.validate_tar_path(filename, path)
      if (len(target) > 0 and target[0] == "/"):
         FATAL("rejecting absolute hard link target: %s: %s -> %s"
               % (filename, path, target))
      if (".." in os.path.normpath(path + "/" + target).split("/")):
         FATAL("rejecting too many up-levels: %s: %s -> %s"
               % (filename, path, target))

   def whiteout_rm_prefix(self, layers, max_i, prefix):
      """Ignore members of all layers from 1 to max_i inclusive that have path
         prefix of prefix. For example, if prefix is foo/bar, then ignore
         foo/bar and foo/bar/baz but not foo/barbaz. Return count of members
         ignored."""
      DEBUG("finding members with prefix: %s" % prefix, v=2)
      prefix = os.path.normpath(prefix)  # "./foo" == "foo"
      ignore_ct = 0
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         if (i > max_i): break
         members2 = list(members.keys())  # copy b/c we'll alter members
         for m in members2:
            if (os.path.commonpath([prefix, m.name]) == prefix):
               ignore_ct += 1
               del members[m]
               DEBUG("layer %d/%d: %s: ignoring %s"
                     % (i, len(layers), lh[:7], m.name), v=2)
      return ignore_ct

   def whiteouts_resolve(self, layers):
      """Resolve whiteouts. See:
         https://github.com/opencontainers/image-spec/blob/master/layer.md"""
      INFO("resolving whiteouts")
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         wo_ct = 0
         ig_ct = 0
         members2 = list(members.keys())  # copy b/c we'll alter members
         for m in members2:
            dir_ = os.path.dirname(m.name)
            filename = os.path.basename(m.name)
            if (filename.startswith(".wh.")):
               wo_ct += 1
               del members[m]
               if (filename == ".wh..wh..opq"):
                  # "Opaque whiteout": remove contents of dir_.
                  DEBUG("found opaque whiteout: %s" % m.name, v=2)
                  ig_ct += self.whiteout_rm_prefix(layers, i - 1, dir_)
               else:
                  # "Explicit whiteout": remove same-name file without ".wh.".
                  DEBUG("found explicit whiteout: %s" % m.name, v=2)
                  ig_ct += self.whiteout_rm_prefix(layers, i - 1,
                                                   dir_ + "/" + filename[4:])
         if (wo_ct > 0):
            DEBUG("layer %d/%d: %s: processed %d whiteouts; %d members ignored"
                  % (i, len(layers), lh[:7], wo_ct, ig_ct))

   def unpack_create_ok(self):
      """Ensure the unpack directory can be created. If the unpack directory
         is already an image, remove it."""
      if (not os.path.exists(self.unpack_path)):
         DEBUG("creating new image: %s" % self.unpack_path)
      else:
         if (not os.path.isdir(self.unpack_path)):
            FATAL("can't flatten: %s exists but is not a directory"
                  % self.unpack_path)
         if (   not os.path.isdir(self.unpack_path + "/bin")
             or not os.path.isdir(self.unpack_path + "/lib")
             or not os.path.isdir(self.unpack_path + "/usr")):
            FATAL("can't flatten: %s exists but does not appear to be an image"
                  % self.unpack_path)
         DEBUG("replacing existing image: %s" % self.unpack_path)
         rmtree(self.unpack_path)

   def unpack_create(self):
      "Ensure the unpack directory exists, replacing or creating if needed."
      self.unpack_create_ok()
      mkdirs(self.unpack_path)

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
      try:
         tree = class_.parser.parse(s)
      except lark.exceptions.UnexpectedInput as x:
         FATAL("image ref syntax, char %d: %s" % (x.column, s))
      except lark.exceptions.UnexpectedEOF as x:
         # We get UnexpectedEOF because of Lark issue #237. This exception
         # doesn't have a column location.
         FATAL("image ref syntax, at end: %s" % s)
      DEBUG(tree.pretty(), v=2)
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

   @property
   def url(self):
      out = ""
      return out

   def copy(self):
      "Return an independent copy of myself."
      return copy.deepcopy(self)

   def defaults_add(self):
      "Set defaults for all empty fields."
      if (self.host is None): self.host = "registry-1.docker.io"
      if (self.port is None): self.port = 443
      if (len(self.path) == 0): self.path = ["library"]
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

class Repo_Downloader:
   """Downloads layers and manifests from an image repository via HTTPS.

      Note that with some registries, authentication is required even for
      anonymous downloads of public images. In this case, we just fetch an
      authentication token anonymously."""

   # The repository protocol follows "ask forgiveness" rather than the
   # standard "ask permission". That is, you request the URL you want, and if
   # it comes back 401 (because either it doesn't exist or you're not
   # authenticated), the response contains a WWW-Authenticate header with the
   # information you need to authenticate. AFAICT, this information is not
   # available any other way. This seems awkward to me, because it requires
   # that all requesting code paths have a contingency for authentication.
   # Therefore, we emulate the standard approach instead.

   __slots__ = ("auth",
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

   class Null_Auth(requests.auth.AuthBase):

      def __call__(self, req):
         return req

   def __init__(self, ref):
      # Need an image ref with all the defaults filled in.
      self.ref = ref.copy()
      self.ref.defaults_add()
      self.auth = None
      self.session = None
      if (verbose >= 2):
         http.client.HTTPConnection.debuglevel = 1

   def _url_of(self, type_, address):
      "Return an appropriate repository URL."
      url_base = "https://%s:%d/v2" % (self.ref.host, self.ref.port)
      return "/".join((url_base, self.ref.path_full, type_, address))

   def authenticate_maybe(self, url):
      """If we need to authenticate, do so using the 401 from url; otherwise
         do nothing."""
      if (self.auth is None):
         DEBUG("requesting auth parameters")
         res = self.get_raw(url, expected_statuses=(401,200))
         if (res.status_code == 200):
            self.auth = self.Null_Auth()
         else:
            if ("WWW-Authenticate" not in res.headers):
               FATAL("WWW-Authenticate header not found")
            auth = res.headers["WWW-Authenticate"]
            if (not auth.startswith("Bearer ")):
               FATAL("authentication scheme is not Bearer")
            # Apparently parsing the WWW-Authenticate header correctly is
            # pretty hard. This is a non-compliant regex kludge [1,2].
            # Alternatives include putting the grammar into Lark (this can be
            # gotten by reading the RFCs enough) or using the www-authenticate
            # library [3].
            #
            # [1]: https://stackoverflow.com/a/1349528
            # [2]: https://stackoverflow.com/a/1547940
            # [3]: https://pypi.org/project/www-authenticate
            authd = dict(re.findall(r'(?:(\w+)[:=] ?"?([\w.~:/?#@!$&()*+,;=\'\[\]-]+)"?)+', auth))
            DEBUG("WWW-Authenticate parse: %s" % authd, v=2)
            for k in ("realm", "service", "scope"):
               if (k not in authd):
                  FATAL("WWW-Authenticate missing key: %s" % k)
            # Request auth token.
            DEBUG("requesting anonymous auth token")
            res = self.get_raw(authd["realm"], expected_statuses=(200,403),
                               params={"service": authd["service"],
                                       "scope": authd["scope"]})
            if (res.status_code == 403):
               INFO("anonymous access rejected")
               username = input("Username: ")
               password = getpass.getpass("Password: ")
               auth = requests.auth.HTTPBasicAuth(username, password)
               res = self.get_raw(authd["realm"], auth=auth,
                                  params={"service": authd["service"],
                                          "scope": authd["scope"]})
            token = res.json()["token"]
            DEBUG("got token: %s..." % (token[:32]))
            self.auth = self.Bearer_Auth(token)

   def close(self):
      if (self.session is not None):
         self.session.close()

   def get(self, url, path, headers=dict()):
      """GET url, passing headers, including authentication and session magic,
         and write the body of the response to path."""
      DEBUG("GETting: %s" % url)
      self.session_init_maybe()
      self.authenticate_maybe(url)
      res = self.get_raw(url, headers)
      try:
         fp = open_(path, "wb")
         ossafe(fp.write, "can't write: %s" % path, res.content)
         ossafe(fp.close, "can't close: %s" % path)
      except OSError as x:
         FATAL("can't write: %s: %s" % (path, x))

   def get_layer(self, hash_, path):
      "GET the layer with hash hash_ and save it at path."
      # /v1/library/hello-world/blobs/<layer-hash>
      url = self._url_of("blobs", "sha256:" + hash_)
      accept = "application/vnd.docker.image.rootfs.diff.tar.gzip"
      self.get(url, path, { "Accept": accept })

   def get_manifest(self, path):
      "GET the manifest for the image and save it at path."
      url = self._url_of("manifests", self.ref.version)
      accept = ["application/vnd.docker.distribution.manifest.v2+json",
                "application/vnd.docker.distribution.manifest.v1+json"]
      self.get(url, path, { "Accept": str(accept) })

   def get_raw(self, url, headers=dict(), auth=None, expected_statuses=(200,),
               **kwargs):
      """GET url, passing headers, with no magic. If auth is None, use
         self.auth (which might also be None). If status is not in
         expected_statuses, barf with a fatal error. Pass kwargs unchanged to
         requests.session.get()."""
      if (auth is None):
         auth = self.auth
      try:
         res = self.session.get(url, headers=headers, auth=auth, **kwargs)
         if (res.status_code not in expected_statuses):
            FATAL("HTTP GET failed; expected status %s but got %d: %s"
                  % (" or ".join(str(i) for i in expected_statuses),
                     res.status_code, res.reason))
      except requests.exceptions.RequestException as x:
         FATAL("HTTP GET failed: %s" % x)
      return res

   def session_init_maybe(self):
      "Initialize session if it's not initialized; otherwise do nothing."
      if (self.session is None):
         DEBUG("initializing session")
         self.session = requests.Session()


class TarFile(tarfile.TarFile):

   # This subclass augments tarfile.TarFile to add safety code. While the
   # tarfile module docs [1] say “do not use this class [TarFile] directly”,
   # they also say “[t]he tarfile.open() function is actually a shortcut” to
   # class method TarFile.open(), and the source code recommends subclassing
   # TarFile [2].
   #
   # [1]: https://docs.python.org/3/library/tarfile.html
   # [2]: https://github.com/python/cpython/blob/2bcd0fe7a5d1a3c3dd99e7e067239a514a780402/Lib/tarfile.py#L2159

   def makefile(self, tarinfo, targetpath):
      """If targetpath is a symlink, stock makefile() overwrites the *target*
         of that symlink rather than replacing the symlink. This is a known,
         but long-standing unfixed, bug in Python [1,2]. To work around this,
         we manually delete targetpath if it exists and is a symlink. See
         issue #819.

         [1]: https://bugs.python.org/issue35483
         [2]: https://bugs.python.org/issue19974"""
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
            pass  # regular file; do nothing (will be overwritten)
         elif (stat.S_ISDIR(st.st_mode)):
            FATAL("can't overwrite directory with regular file: %s"
                  % targetpath)
         elif (stat.S_ISLNK(st.st_mode)):
            unlink(targetpath)
         else:
            FATAL("invalid file type 0%o in previous layer; see inode(7): %s"
                  % (stat.S_IFMT(st.st_mode), targetpath))
      super().makefile(tarinfo, targetpath)


## Supporting functions ##

def DEBUG(*args, v=1, **kwargs):
   if (verbose >= v):
      log(color="36m", *args, **kwargs)

def ERROR(*args, **kwargs):
   log(color="31m", prefix="error: ", *args, **kwargs)

def FATAL(*args, **kwargs):
   ERROR(*args, **kwargs)
   sys.exit(1)

def INFO(*args, **kwargs):
   log(*args, **kwargs)

def WARNING(*args, **kwargs):
   log(color="31m", prefix="warning: ", *args, **kwargs)

def cmd(args, env=None):
   DEBUG("environment: %s" % env)
   DEBUG("executing: %s" % args)
   color_set("33m", sys.stdout)
   cp = subprocess.run(args, env=env, stdin=subprocess.DEVNULL)
   color_reset(sys.stdout)
   if (cp.returncode):
      FATAL("command failed with code %d: %s" % (cp.returncode, args[0]))

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
   for (p, v) in depfails:
      ERROR("%s dependency: %s" % (p, v))
   if (len(depfails) > 0):
      sys.exit(1)

def file_ensure_exists(path):
   fp = open_(path, "a")
   fp.close()

def file_write(path, content, mode=None):
   fp = open_(path, "wt")
   ossafe(fp.write, "can't write: %s" % path, content)
   if (mode is not None):
      ossafe(os.chmod, "can't chmod 0%o: %s" % (mode, path))
   fp.close()

def log(*args, color=None, prefix="", **kwargs):
   if (color is not None):
      color_set(color, log_fp)
   if (log_festoon):
      prefix = ("%5d %s  %s"
                % (os.getpid(),
                   datetime.datetime.now().isoformat(timespec="milliseconds"),
                   prefix))
   print(prefix, file=log_fp, end="")
   print(flush=True, file=log_fp, *args, **kwargs)
   if (color is not None):
      color_reset(log_fp)

def log_setup(verbose_):
   global verbose, log_festoon, log_fp
   assert (0 <= verbose_ <= 2)
   verbose = verbose_
   if ("CH_LOG_FESTOON" in os.environ):
      log_festoon = True
   file_ = os.getenv("CH_LOG_FILE")
   if (file_ is not None):
      verbose = max(verbose_, 1)
      log_fp = open_(file_, "at")
   atexit.register(color_reset, log_fp)

def mkdirs(path):
   DEBUG("ensuring directory: " + path)
   try:
      os.makedirs(path, exist_ok=True)
   except OSError as x:
      ch.FATAL("can't create directory: %s: %s: %s"
               % (path, x.filename, x.strerror))

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

def rmtree(path):
   if (os.path.isdir(path)):
      DEBUG("deleting directory: " + path)
      try:
         shutil.rmtree(path)
      except OSError as x:
         ch.FATAL("can't recursively delete directory %s: %s: %s"
                  % (path, x.filename, x.strerror))
   else:
      assert False, "unimplemented"

def storage_env():
   """Return path to builder storage as configured by $CH_GROW_STORAGE, or the
      default if that's not set."""
   try:
      return os.environ["CH_GROW_STORAGE"]
   except KeyError:
      return storage_default()

def storage_default():
   # FIXME: Perhaps we should use getpass.getuser() instead of the $USER
   # environment variable? It seems a lot more robust. But, (1) we'd have
   # to match it in some scripts and (2) it makes the documentation less
   # clear becase we have to explain the fallback behavior.
   try:
      username = os.environ["USER"]
   except KeyError:
      FATAL("can't get username: $USER not set")
   return "/var/tmp/%s/ch-grow" % username

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
      ch.FATAL("can't symlink: %s -> %s: %s" % (source, target, x.strerror))

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
   """Yield values of all child terminals of type type_, or empty list if none
      found."""
   for j in tree.children:
      if (isinstance(j, lark.lexer.Token) and j.type == tname):
         yield j.value

def unlink(path, *args, **kwargs):
   "Error-checking wrapper for os.unlink()."
   ossafe(os.unlink, "can't unlink: %s" % path, path)
