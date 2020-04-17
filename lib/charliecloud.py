import argparse
import collections
import copy
import http.client
import json
import logging
import os
import shutil
import sys
import tarfile
import types

import version


## Imports not in standard library ##

# These are messy because we need --version and --help even if a dependency is
# missing.

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
   m = types.ModuleType("lark")
   class Visitor_Mock(object):
      pass
   m.Visitor = Visitor_Mock
   lark = m

try:
   import requests
except ImportError:
   depfails.append(("missing", 'Python module "requests"'))


## Globals ##

# Verbosity level. Can be 0, 1, or 2.
verbose = 0

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

?instruction: _WS? ( cmd | copy | arg | env | from_ | run | workdir )

cmd: "CMD"i _WS LINE _NEWLINES

copy: "COPY"i ( _WS copy_chown )? ( copy_shell ) _NEWLINES
copy_chown: "--chown" "=" /[^ \t\n]+/
copy_shell: _WS WORD ( _WS WORD )+

arg: "ARG"i _WS ( arg_bare | arg_equals ) _NEWLINES
arg_bare: WORD
arg_equals: WORD "=" ( WORD | STRING_QUOTED )

env: "ENV"i _WS ( env_space | env_equalses ) _NEWLINES
env_space: WORD _WS LINE
env_equalses: env_equals ( _WS env_equals )*
env_equals: WORD "=" ( WORD | STRING_QUOTED )

from_: "FROM"i _WS image_ref [ _WS from_alias ] _NEWLINES
from_alias: "AS"i _WS IR_PATH_COMPONENT  // FIXME: undocumented; this is guess

run: "RUN"i _WS ( run_exec | run_shell ) _NEWLINES
run_exec.2: _string_list
run_shell: LINE

workdir: "WORKDIR"i _WS LINE _NEWLINES


/// Common ///

HEX_STRING: /[0-9A-Fa-f]+/
LINE: ( LINE_CONTINUE | /[^\n]/ )+
WORD: /[^ \t\n=]/+

_string_list: "[" _WS? STRING_QUOTED ( "," _WS? STRING_QUOTED )* _WS? "]"

LINE_CONTINUE: "\\\n"
%ignore LINE_CONTINUE

_COMMENT: _WS? /#[^\n]*/ _NEWLINES
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
                "unpack_dir")

   def __init__(self, ref, download_cache, unpack_dir, image_subdir=None):
      self.ref = ref
      self.download_cache = download_cache
      self.unpack_dir = unpack_dir
      if (image_subdir is None):
         self.image_subdir = self.ref.for_path
      else:
         self.image_subdir = image_subdir
      self.layer_hashes = None

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
      assert False, "unimplemented"

   def download(self, use_cache=True):
      """Download image manifest and layers according to origin and put them
         in the download cache. By default, any components already in the
         cache are skipped; if use_cache is False, download them anyway,
         overwriting what's in the cache."""
      def _url(type_, address):
         url_base = "https://%s:%d/v2" % (dl.ref.host, dl.ref.port)
         return "/".join((url_base, dl.ref.path_full, type_, address))
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      dl = Repo_Downloader(self.ref)
      DEBUG("downloading image: %s" % dl.ref)
      mkdirs(self.download_cache)
      # manifest
      if (os.path.exists(self.manifest_path) and use_cache):
         INFO("manifest: using existing file")
      else:
         INFO("manifest: downloading")
         url = _url("manifests", dl.ref.version)
         DEBUG(url)
         accept = "application/vnd.docker.distribution.manifest.v2+json"
         res = http_get(dl.session, url, { "Accept": accept })
         with open(self.manifest_path, "wb") as fp:
            fp.write(res.content)  # FIXME: catch exceptions
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
            # /v1/library/hello-world/blobs/<layer-hash>
            url = _url("blobs", "sha256:" + lh)
            DEBUG(url)
            accept = "application/vnd.docker.image.rootfs.diff.tar.gzip"
            res = http_get(dl.session, url, { "Accept": accept })
            with open(path, "wb") as fp:
               fp.write(res.content)  # FIXME: catch exceptions
      dl.close()

   def flatten(self):
      "Flatten the layers in the download cache into the unpack directory."
      layers = self.layers_read()
      self.validate_members(layers)
      self.whiteouts_resolve(layers)
      INFO("flattening image")
      self.unpack_create()
      for (i, (lh, (fp, members))) in enumerate(layers.items(), start=1):
         INFO("layer %d/%d: %s: extracting" % (i, len(layers), lh[:7]))
         fp.extractall(path=self.unpack_path, members=members)

   def layer_hashes_load(self):
      "Load the layer hashes from the manifest file."
      try:
         fp = open(self.manifest_path, "rt", encoding="UTF-8")
      except OSError as x:
         FATAL("can't open manifest file: %s: %s"
               % (self.manifest_path, x.strerror))
      try:
         doc = json.load(fp)
      except json.JSONDecodeError as x:
         FATAL("can't parse manifest file: %s:%d: %s"
               % (self.manifest_path, x.lineno, x.msg))
      try:
         self.layer_hashes = [i["digest"].split(":")[1] for i in doc["layers"]]
      except (AttributeError, KeyError, IndexError):
         FATAL("can't parse manifest file: %s" % self.manifest_path)

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
      for (i, lh) in enumerate(self.layer_hashes, start=1):
         INFO("layer %d/%d: %s: listing" % (i, len(self.layer_hashes), lh[:7]))
         path = self.layer_path(lh)
         try:
            fp = tarfile.open(path)
            members_list = fp.getmembers()  # reads whole file :(
         except tarfile.TarError as x:
            FATAL("cannot open: %s: %s" % (path, x))
         members = collections.OrderedDict([(m, None) for m in members_list])
         layers[lh] = TT(fp, members)
      return layers

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

   def unpack_create(self):
      "Ensure the unpack directory exists, replacing or creating if needed."
      if (not os.path.exists(self.unpack_path)):
         INFO("creating new image: %s" % self.unpack_path)
      else:
         if (not os.path.isdir(self.unpack_path)):
            FATAL("can't flatten: %s exists but is not a directory"
                  % self.unpack_path)
         if (   not os.path.isdir(self.unpack_path + "/bin")
             or not os.path.isdir(self.unpack_path + "/lib")
             or not os.path.isdir(self.unpack_path + "/usr")):
            FATAL("can't flatten: %s exists but does not appear to be an image"
                  % self.unpack_path)
         INFO("replacing existing image: %s" % self.unpack_path)
         def fail(function, path, excinfo):
            FATAL("can't flatten: %s: %s" % (path, excinfo[1]))
         shutil.rmtree(self.unpack_path, onerror=fail)
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

   @staticmethod
   def parse(s):
      if ("%" in s):
         s = s.replace("%", "/")
      parser = lark.Lark("?start: image_ref\n" + GRAMMAR, parser="earley",
                         propagate_positions=True)
      try:
         tree = parser.parse(s)
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
      Currently, only Docker Hub is supported."""

   __slots__ = ("ref",
                "_session")

   def __init__(self, ref):
      # Need an image ref with all the defaults filled in.
      self.ref = ref.copy()
      self.ref.defaults_add()
      assert (self.ref.host == "registry-1.docker.io")
      assert (self.ref.port == 443)
      self._session = None
      if (verbose >= 2):
         http.client.HTTPConnection.debuglevel = 1

   @property
   # I'm a bit uncomfortable because this feels like too much magic for a
   # property. However, if we do it this way, it enables the caller to simply
   # refer to the session when needed, without a conditional to initialize it.
   # An alternative would be to make it a normal function, suggesting more is
   # going on; maybe that's a FIXME.
   def session(self):
      "The Requests session, magically setting one up if needed."
      if (self._session is None):
         DEBUG("initializing session")
         s = requests.Session()
         # First, we need an authorization token. This has to be fetched from
         # a separate host. Currently, this only works for public Docker Hub.
         DEBUG("fetching auth token")
         r = s.get("https://auth.docker.io/token",
                   params={"service": "registry.docker.io",
                           "scope": "repository:%s:pull" % self.ref.path_full})
         token = r.json()["token"]
         DEBUG("got token: %s..." % (token[:32]))
         s.headers.update({ "Authorization": "Bearer %s" % token })
         self._session = s
      return self._session

   def close(self):
      if (self._session is not None):
         self._session.close()


## Supporting functions ##

def DEBUG(*args, v=1, **kwargs):
   if (verbose >= v):
      color("36m", sys.stderr)
      print(flush=True, file=sys.stderr, *args, **kwargs)
      color_reset(sys.stderr)

def ERROR(*args, **kwargs):
   color("31m", sys.stderr)
   print("error: ", file=sys.stderr, end="")
   print(flush=True, file=sys.stderr, *args, **kwargs)
   color_reset(sys.stderr)

def FATAL(*args, **kwargs):
   ERROR(*args, **kwargs)
   sys.exit(1)

def INFO(*args, **kwargs):
   print(flush=True, *args, **kwargs)

def WARNING(*args, **kwargs):
   color("31m", sys.stderr)
   print("warning: ", file=sys.stderr, end="")
   print(flush=True, file=sys.stderr, *args, **kwargs)
   color_reset(sys.stderr)

def color(color, fp):
   if (fp.isatty()):
      print("\033[" + color, end="", flush=True, file=fp)

def color_reset(*fps):
   for fp in fps:
      color("0m", fp)

def dependencies_check():
   """Check more dependencies. If any dependency problems found, here or above
      (e.g., lark module checked at import time), then complain and exit."""
   for (p, v) in depfails:
      ERROR("%s dependency: %s" % (p, v))
   if (len(depfails) > 0):
      sys.exit(1)

def http_get(session, url, headers):
   try:
      res = session.get(url, headers=headers)
      res.raise_for_status()
   except requests.RequestException as x:
      FATAL("download failed: %s" % x)
   return res

def mkdirs(path):
   DEBUG("ensuring directory: " + path)
   os.makedirs(path, exist_ok=True)

def tree_child(tree, cname):
   """Locate a descendant subtree named cname using breadth-first search and
      return it. If no such subtree exists, return None."""
   for st in tree.iter_subtrees_topdown():
      if (st.data == cname):
         return st
   return None

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
