import sys

import lark

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
