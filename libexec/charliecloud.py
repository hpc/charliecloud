#!/usr/bin/python3

# Library for common ch-grow and ch-pull functions.

import charliecloud # FIXME: merge
import collections
import lark
import logging
import json
import os
import re
import requests
import shutil
import sys
import tarfile

from http.client import HTTPConnection

## Globals ##
session = requests.Session()

## Constants ##

# FIXME: move these to defaults; add argument handling
registryBase = 'https://registry-1.docker.io'
authBase     = 'https://auth.docker.io'
authService  = 'registry.docker.io'

# Accepted Docker V2 media types. See
# https://docs.docker.com/registry/spec/manifest-v2-2/
# FIXME: We only use MF_SCHEMA2 and LAYERS in this script, do we care about
# declaring the others for future work?
MF_SCHEMA1 = 'application/vnd.docker.distribution.manifest.v1+json'
MF_SCHEMA2 = 'application/vnd.docker.distribution.manifest.v2+json'
MF_LIST    = 'application/vnd.docker.distribution.manifest.list.v2+json'
C_CONFIG   = 'application/vnd.docker.container.image.v1+json'
LAYER      = 'application/vnd.docker.image.rootfs.diff.tar.gzip'
PLUGINS    = 'application/vnd.docker.plugin.v1+json'

PROXIES = { "HTTP_PROXY":  os.environ.get("HTTP_PROXY"),
            "HTTPS_PROXY": os.environ.get("HTTPS_PROXY"),
            "FTP_PROXY":   os.environ.get("FTP_PROXY"),
            "NO_PROXY":    os.environ.get("NO_PROXY"),
            "http_proxy":  os.environ.get("http_proxy"),
            "https_proxy": os.environ.get("https_proxy"),
            "ftp_proxy":   os.environ.get("ftp_proxy"),
            "no_proxy":    os.environ.get("no_proxy"),
}

# This is a general grammar for all the parsing we need to do. As such, you
# must prepend a start rule before use.
# FIXME: ch-grow also assigns this variable
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

## Classes ##

class Image_Ref:
   """Reference to an image in a repository. The constructor takes one
      argument, which is interpreted differently depending on type:

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

   __slots__ = ("hostname",
                "port",
                "path",
                "name",
                "tag",
                "digest")

   def __init__(self, src=None):
      self.hostname = None
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
      return "FIXME"

   @staticmethod
   def parse(s):
      parser = lark.Lark("?start: image_ref\n" + GRAMMAR, parser="earley",
                         propagate_positions=True)
      tree = parser.parse(s)
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
  hostname  %s
  port      %s
  path      %s
  name      %s
  tag       %s
  digest    %s\
""" % tuple(  [str(self), self.for_path]
            + [fmt(i) for i in (self.hostname, self.port, self.path,
                                self.name, self.tag, self.digest)])

   @property
   def for_path(self):
      return str(self).replace("/", "%")

   def defaults_add(self):
      "Set defaults for all empty fields."
      if (self.hostname is None): self.hostname = "registry-1.docker.io"
      if (self.port is None): self.port = 443
      if (self.path is None): self.path = "library"
      if (self.tag is None and self.digest is None): self.tag = "latest"

   def from_tree(self, t):
      self.hostname = tree_child(t, "ir_hostport", "IR_HOST")
      self.port = tree_child(t, "ir_hostport", "IR_PORT")
      if (self.port is not None):
         self.port = int(self.port)
      self.path = list(tree_child_terminals(t, "ir_path", "IR_PATH_COMPONENT"))
      self.name = tree_child(t, "ir_name", "IR_PATH_COMPONENT")
      self.tag = tree_child(t, "ir_tag", "IR_TAG")
      self.digest = tree_child(t, "ir_digest", "HEX_STRING")
      # Resolve grammar ambiguity.
      if (    self.hostname is not None
          and "." not in self.hostname
          and self.port is None):
         self.path.insert(0, self.hostname)
         self.hostname = None


class Image:
    # FIXME: better description
    """Image fetch and unpack driver class."""

    def __init__(self, src):
        self.ref = Image_Ref(src)

    def download(self, dst):
    # FIXME: better description.
    """download an image from v2 repository."""
        # Prefer image digest for pull reference.
        if self.digest:
            pull_reference = self.digest
        else:
            pull_reference = self.tag

        self.session = MySession(self)
        self.manifest = self.data_fetch('manifests',
                                        MF_SCHEMA2,
                                        pull_reference)

        print("downloading image '{}:{}' ...".format(self.name, self.tag))

        # Store manifest file as
        # CH_GROW_STORAGE/manifests/IMAGE:TAG/manifest.json. Note: IMAGE itself
        # can be a parent directory. For example, the image
        # 'charliecloud/whiteout:2020-01-10` manifest would be written as:
        # /var/tmp/ch-grow/manifests/charliecloud/whiteout:2020-01-10/HASH
        mdir = os.path.join(dst, 'manifests/{}:{}'.format(self.name,
                                                          self.tag))
        if not os.path.isdir(mdir):
            os.makedirs(mdir)
        os.chdir(mdir)
        open(os.path.join(mdir,
                          'manifest.json'), 'wb').write(self.manifest.content)

        # Make layers directory.
        ldir = os.path.join(dst, 'layers')
        if not os.path.isdir(ldir):
            os.makedirs(ldir)
        os.chdir(ldir)

        # Pull layer from repository if absent from the layers dir.
        for layer in self.manifest.json().get('layers'):
            name = layer.get('digest').split('sha256:')[-1]
            if not os.path.exists(name):
                INFO("fetching layer '{}'".format(name))
                request = self.data_fetch('blobs', 'layer', layer.get('digest'))
                open(name, 'wb').write(request.content)
                if not tarfile.is_tarfile(name):
                    FATAL("'{}' does not appear to be a tarfile".format(layer))

    def data_fetch(self, branch, media, reference):
        # FIXME: better description.
        """fetch image data, e.g., blob, layer, manifest, from a v2 image
        repository"""
        self.session.headers.update({ 'Accept': media })
        URL = "{}/v2/{}/{}/{}".format(registryBase,
                                      self.name,
                                      branch,
                                      reference)
        #DEBUG("GET {}".format(URL))
        #DEBUG('{}'.format(self.session.headers))
        try:
            response = session.get(URL,
                                   headers=self.session.headers,
                                   proxies=PROXIES)
            response.raise_for_status()
        except requests.HTTPError as http_err:
            FATAL('HTTP error: {}'.format(http_err))
        except Exception as err:
            FATAL('non HTTP error occured: {}'.format(err))
        return response

    def unpack(self, dst):
        mdir = os.path.join(dst, 'manifests/{}:{}'.format(self.name, self.tag))

        # Download image if manifest doesn't exist locally.
        if not os.path.exists(os.path.join(mdir, 'manifest.json')):
            self.download(dst)

        print("unpacking image '{}:{}' ...".format(self.name, self.tag))

        ldir = os.path.join(dst, 'layers')
        if not os.path.isdir(ldir):
            os.makedirs(ldir)
        os.chdir(ldir)

        # Read manifest layer list; create a dict of key-value pairs where
        # k = layer hash and v = a tarfile object.
        mf_json   = json.load(open(os.path.join(mdir, 'manifest.json'), 'r'))
        layers_d  = dict()
        for layer in mf_json.get('layers'):
            layer = layer.get('digest')
            tar = layer.split('sha256:')[-1] # exclude algorithm
            if not os.path.exists(tar):
                FATAL("{} doesn't exist in storage.".format(tar))
            if not tarfile.is_tarfile(tar):
                FATAL("{} is not a valid tar archive".format(tar))
            tf = tarfile.open(tar, 'r')
            layers_d.update({tar : tf})

        imgdir = os.path.join(dst, 'img/{}:{}'.format(self.name, self.tag))
        if os.path.isdir(imgdir):
            INFO("replacing image {}:{}".format(self.name, self.tag))
            shutil.rmtree(imgdir)
        os.makedirs(imgdir)
        os.chdir(imgdir)

        # Iterate through layers; process and unpack to STORAGE/img/IMAGE:TAG.
        # Primary operations: 1) exclude device files; 2) fail if one or more
        # file(s) with a dangerous absolute path is encountered; and 3) remove
        # file target specified by whiteout file in current layer from most recent
        # unpacked layer in STORAGE/img/IMAGE:TAG.
        dev_ct = 0
        wh_ct  = 0
        for k, v in layers_d.items():
            tf_info = v.getmembers()
            tf_members = list()
            for m in tf_info:
                if m.isdev():
                    dev_ct += 1
                    DEBUG('ignoring device file {}'.format(m.name))
                # FIXME: handle opaque whiteout files
                elif re.search('\.wh\..*', m.name):
                    wh_ct += 1
                    DEBUG('whiteout found: {}'.format(m.name))
                    wh = os.path.basename(m.name)
                    wh_dirname = os.path.dirname(m.name)
                    wh_target = os.path.join(wh_dirname, wh.split('.wh.')[-1])
                    if os.path.exists(wh_target):
                        DEBUG('removing {}'.format(wh_target))
                        if os.path.isdir(wh_target):
                            shutil.rmtree(wh_target)
                        else:
                           os.remove(wh_target)
                    else:
                       FATAL("whiteout target {} doesn't exist".format(wh_target))
                elif re.search('^\.\./.*', m.name) or re.search('^/.*', m.name):
                    FATAL("dangerous extraction path '{}'".format(m.name))
                else:
                    tf_members.append(m)

            INFO('extracting layer {}'.format(k))
            v.extractall(members=tf_members)

        print('image successfully unpacked.')
        if dev_ct > 0:
            INFO("{} device files ignored.".format(dev_ct))
        if wh_ct > 0:
            INFO("{} whiteout files handled.".format(wh_ct))


class MySession:
    def __init__(self, image):
        self.token   = self.get_token(image)
        self.headers = self.get_headers()

    def get_headers(self):
        return {'Authorization': 'Bearer {}'.format(self.token)}

    def get_token(self, image):
        tokenService = '{}/token?service={}'.format(authBase, authService)
        scopeRepo    = '&scope=repository:{}:pull'.format(image.name)
        authURL      = tokenService + scopeRepo
        return session.get(authURL, proxies=PROXIES).json()['token']


## Supporting functions ##

def DEBUG(*args, **kwargs):
   if (verbose):
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

def log_http():
    logging.basicConfig(format='%(levelname)s:%(message)s')
    HTTPConnection.debuglevel = 1
    logging.getLogger().setLevel(logging.DEBUG)
    rlog = logging.getLogger("requests.packages.urllib3").setLevel(logging.DEBUG)

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
