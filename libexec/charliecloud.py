import copy
import http.client
import json
import logging
import os
import sys

import lark
import requests

# This is a general grammar for all the parsing we need to do. As such, you
# must prepend a start rule before use.
GRAMMAR = r"""

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
HEX_STRING: /[0-9A-Fa-f]+/
"""

## Globals ##

verbose = 0


## Classes ##

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
   def session(self):
      "Return the Requests session, or set one up if one doesn't exist."
      if (self._session is None):
         DEBUG("initializing session")
         s = requests.Session()
         # First, we need an authorization token. This has to be fetched from
         # a separate host. Currently, this only works for public Docker Hub.
         DEBUG("fetching auth token")
         r = s.get("https://auth.docker.io/token",
                   params={ "service": "registry.docker.io",
                            "scope": (  "repository:%s:pull"
                                      % "library/hello-world") })
         token = r.json()["token"]
         DEBUG("got token: %s..." % (token[:32]))
         s.headers.update({ "Authorization": "Bearer %s" % token })
         self._session = s
      return self._session

   def close(self):
      if (self._session is not None):
         self._session.close()


class Image:
   """Container image object.

      Constructor arguments:

        id_.............. Image_Ref object to identify the image.

        download_cache .. Directory containing the download cache; this is
                          where layers and manifests go. If None,
                          download-related operations will not be available.

        unpack_dir ...... Directory containing unpacked images.

        image_subdir .... Subdirectory of unpack_dir to put unpacked image in.
                          If None, infer from id; if the empty string,
                          unpack_dir will be used directly."""

   __slots__ = ("id",
                "download_cache",
                "image_subdir",
                "layer_hashes",
                "unpack_dir")

   def __init__(self, id_, download_cache, unpack_dir, image_subdir):
      self.id = id_
      self.download_cache = download_cache
      self.unpack_dir = unpack_dir
      if (image_subdir is None):
         self.image_subdir = self.id.for_path
      else:
         self.image_subdir = image_subdir

   @property
   def unpack_path(self):
      return "%s/%s" % (self.unpack_dir, self.image_subdir)

   @property
   def manifest_path(self):
      return "%s/%s.manifest.json" % (self.download_cache, self.id.for_path)

   def commit(self):
      """Commit the current unpack directory into the layer cache."""
      assert False, "unimplemented"

   def copy_unpacked(self, other):
      """Copy the unpack directory of Image other to my unpack directory."""
      assert False, "unimplemente"

   def download(self, use_cache=True):
      """Download image manifest and layers according to origin and put them
         in the download cache. By default, any components already in the
         cache are skipped; if use_cache is False, download them anyway,
         overwriting what's in the cache."""
      def _url(type_, address):
         url_base = "https://%s:%d/v2" % (dl.ref.host, dl.ref.port)
         return "/".join((url_base, dl.ref.path_full, type_, address))
      # Spec: https://docs.docker.com/registry/spec/manifest-v2-2/
      dl = Repo_Downloader(self.id)
      DEBUG("downloading image: %s" % dl.ref)
      mkdirs(self.download_cache)
      # manifest
      if (os.path.exists(self.manifest_path) and use_cache):
         INFO("manifest: using existing")
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
            INFO("using existing")
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

   def layer_hashes_load(self):
      try:
         fp = open(self.manifest_path, "rb")
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
      "Return the path to layer layer_hash."
      return "%s/%s.tar.gz" % (self.download_cache, layer_hash)

   def unpack_download(self):
      "Unpack the layers in the download cache into the unpack directory."
      ...


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
                           parge (e.g., a Dockerfile).

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
         FATAL("image ref syntax error, char %d: %s" % (x.column, s))
      except lark.exceptions.UnexpectedEOF as x:
         # We get UnexpectedEOF because of Lark issue #237. This exception
         # doesn't have a column location.
         FATAL("image ref syntax error, at end: %s" % s)
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
url:          %s
fields:
  host    %s
  port    %s
  path    %s
  name    %s
  tag     %s
  digest  %s\
""" % tuple(  [str(self), self.for_path, self.url]
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
      self.host = tree_child(t, "ir_hostport", "IR_HOST")
      self.port = tree_child(t, "ir_hostport", "IR_PORT")
      if (self.port is not None):
         self.port = int(self.port)
      self.path = list(tree_child_terminals(t, "ir_path", "IR_PATH_COMPONENT"))
      self.name = tree_child(t, "ir_name", "IR_PATH_COMPONENT")
      self.tag = tree_child(t, "ir_tag", "IR_TAG")
      self.digest = tree_child(t, "ir_digest", "HEX_STRING")
      # Resolve grammar ambiguity for hostnames w/o dot or port.
      if (    self.host is not None
          and "." not in self.host
          and self.port is None):
         self.path.insert(0, self.host)
         self.host = None


## Supporting functions ##

def DEBUG(*args, v=1, **kwargs):
   if (verbose >= v):
      color("36m", sys.stderr)
      print(flush=True, file=sys.stderr, *args, **kwargs)
      color_reset(sys.stderr)

def ERROR(*args, **kwargs):
   color("31m", sys.stderr)
   print(flush=True, file=sys.stderr, *args, **kwargs)
   color_reset(sys.stderr)

def FATAL(*args, **kwargs):
   ERROR(*args, **kwargs)
   sys.exit(1)

def INFO(*args, **kwargs):
   print(flush=True, *args, **kwargs)

def color(color, fp):
   if (fp.isatty()):
      print("\033[" + color, end="", flush=True, file=fp)

def color_reset(*fps):
   for fp in fps:
      color("0m", fp)

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

def tree_child(tree, cname, tname, i=0):
   """Locate a descendant subtree named cname using breadth-first search and
      return its first child terminal named tname. If no such subtree exists,
      or it doesn't have such a terminal, return None."""
   for d in tree.iter_subtrees_topdown():
      if (d.data == cname):
         return tree_terminal(d, tname, i)
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
