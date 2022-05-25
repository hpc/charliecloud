# Implementation of "ch-image build".

import abc
import ast
import glob
import json
import os
import os.path
import re
import shutil
import struct
import sys

import charliecloud as ch
import build_cache as bu
import fakeroot
import pull


## Globals ##

# Namespace from command line arguments. FIXME: be more tidy about this ...
cli = None

# Fakeroot configuration (initialized during FROM).
fakeroot_config = None

# Images that we are building. Each stage gets its own image. In this
# dictionary, an image appears exactly once or twice. All images appear with
# an int key counting stages up from zero. Images with a name (e.g., "FROM ...
# AS foo") have a second string key of the name.
images = dict()
# Number of stages. This is obtained by counting FROM instructions in the
# parse tree, so we can use it for error checking.
image_ct = None


## Imports not in standard library ##

# See charliecloud.py for the messy import of this.
lark = ch.lark


## Main ##

def main(cli_):

   # CLI namespace. :P
   global cli
   cli = cli_

   # Check argument validity.
   if (cli.force and cli.no_force_detect):
      ch.FATAL("--force and --no-force-detect are incompatible")

   # Infer input file if needed.
   if (cli.file is None):
      cli.file = cli.context + "/Dockerfile"

   # Infer image name if needed.
   if (cli.tag is None):
      path = os.path.basename(cli.file)
      if ("." in path):
         (base, ext_all) = str(path).split(".", maxsplit=1)
         (base_all, ext_last) = str(path).rsplit(".", maxsplit=1)
      else:
         base = None
         ext_last = None
      if (base == "Dockerfile"):
         cli.tag = ext_all
         ch.VERBOSE("inferring name from Dockerfile extension: %s" % cli.tag)
      elif (ext_last == "dockerfile"):
         cli.tag = base_all
         ch.VERBOSE("inferring name from Dockerfile basename: %s" % cli.tag)
      elif (os.path.abspath(cli.context) != "/"):
         cli.tag = os.path.basename(os.path.abspath(cli.context))
         ch.VERBOSE("inferring name from context directory: %s" % cli.tag)
      else:
         assert (os.path.abspath(cli.context) == "/")
         cli.tag = "root"
         ch.VERBOSE("inferring name with root context directory: %s" % cli.tag)
      cli.tag = re.sub(r"[^a-z0-9_.-]", "", cli.tag.lower())
      ch.INFO("inferred image name: %s" % cli.tag)

   # Deal with build arguments.
   def build_arg_get(arg):
      kv = arg.split("=")
      if (len(kv) == 2):
         return kv
      else:
         v = os.getenv(kv[0])
         if (v is None):
            ch.FATAL("--build-arg: %s: no value and not in environment" % kv[0])
         return (kv[0], v)
   cli.build_arg = dict( build_arg_get(i) for i in cli.build_arg )
   ch.DEBUG(cli)

   # Guess whether the context is a URL, and error out if so. This can be a
   # typical looking URL e.g. "https://..." or also something like
   # "git@github.com:...". The line noise in the second line of the regex is
   # to match this second form. Username and host characters from
   # https://tools.ietf.org/html/rfc3986.
   if (re.search(r"""  ^((git|git+ssh|http|https|ssh)://
                     | ^[\w.~%!$&'\(\)\*\+,;=-]+@[\w.~%!$&'\(\)\*\+,;=-]+:)""",
                 cli.context, re.VERBOSE) is not None):
      ch.FATAL("not yet supported: issue #773: URL context: %s" % cli.context)
   if (os.path.exists(cli.context + "/.dockerignore")):
      ch.WARNING("not yet supported, ignored: issue #777: .dockerignore file")

   # Read input file.
   if (cli.file == "-" or cli.context == "-"):
      text = ch.ossafe(sys.stdin.read, "can't read stdin")
   else:
      fp = ch.open_(cli.file, "rt")
      text = ch.ossafe(fp.read, "can't read: %s" % cli.file)
      ch.close_(fp)

   # Parse it.
   parser = lark.Lark("?start: dockerfile\n" + ch.GRAMMAR,
                      parser="earley", propagate_positions=True)
   # Avoid Lark issue #237: lark.exceptions.UnexpectedEOF if the file does not
   # end in newline.
   text += "\n"
   try:
      tree = parser.parse(text)
   except lark.exceptions.UnexpectedInput as x:
      ch.VERBOSE(x)  # noise about what was expected in the grammar
      ch.FATAL("can't parse: %s:%d,%d\n\n%s"
               % (cli.file, x.line, x.column, x.get_context(text, 39)))
   ch.VERBOSE(tree.pretty())

   # Sometimes we exit after parsing.
   if (cli.parse_only):
      sys.exit(0)

   # Count the number of stages (i.e., FROM instructions)
   global image_ct
   image_ct = sum(1 for i in ch.tree_children(tree, "from_"))

   # Traverse the tree and do what it says.
   #
   # We don't actually care whether the tree is traversed breadth-first or
   # depth-first, but we *do* care that instruction nodes are visited in
   # order. Neither visit() nor visit_topdown() are documented as of
   # 2020-06-11 [1], but examining source code [2] shows that visit_topdown()
   # uses Tree.iter_trees_topdown(), which *is* documented to be in-order [3].
   #
   # This change seems to have been made in 0.8.6 (see PR #761); before then,
   # visit() was in order. Therefore, we call that instead, if visit_topdown()
   # is not present, to improve compatibility (see issue #792).
   #
   # [1]: https://lark-parser.readthedocs.io/en/latest/visitors/#visitors
   # [2]: https://github.com/lark-parser/lark/blob/445c8d4/lark/visitors.py#L211
   # [3]: https://lark-parser.readthedocs.io/en/latest/classes/#tree
   ml = Main_Loop()
   if (hasattr(ml, 'visit_topdown')):
      ml.visit_topdown(tree)
   else:
      ml.visit(tree)
   if (ml.instruction_total_ct > 0):
      if (ml.miss_ct == 0):
         ml.inst_prev.checkout()
      ml.inst_prev.ready()

   # Check that all build arguments were consumed.
   if (len(cli.build_arg) != 0):
      ch.FATAL("--build-arg: not consumed: " + " ".join(cli.build_arg.keys()))

   # Print summary & we're done.
   if (ml.instruction_total_ct == 0):
      ch.FATAL("no instructions found: %s" % cli.file)
   assert (ml.inst_prev.image_i + 1 == image_ct)  # should’ve errored already
   if (cli.force and ml.miss_ct != 0):
      if (fakeroot_config.inject_ct == 0):
         assert (not fakeroot_config.init_done)
         ch.WARNING("--force specified, but nothing to do")
      else:
         ch.INFO("--force: init OK & modified %d RUN instructions"
                 % fakeroot_config.inject_ct)
   ch.INFO("grown in %d instructions: %s"
           % (ml.instruction_total_ct, ml.inst_prev.image))
   # FIXME: remove when we're done encouraging people to use the build cache.
   if (isinstance(bu.cache, bu.Disabled_Cache)):
      ch.INFO("build slow? consider enabling the new build cache",
              "https://hpc.github.io/charliecloud/command-usage.html#build-cache")


class Main_Loop(lark.Visitor):

   __slots__ = ("instruction_total_ct",
                "miss_ct",    # number of misses during this stage
                "inst_prev")  # last instruction executed

   def __init__(self, *args, **kwargs):
      self.miss_ct = 0
      self.inst_prev = None
      self.instruction_total_ct = 0
      super().__init__(*args, **kwargs)

   def __default__(self, tree):
      class_ = "I_" + tree.data
      if (class_ in globals()):
         inst = globals()[class_](tree)
         if (self.instruction_total_ct == 0):
            if (   isinstance(inst, I_directive)
                or isinstance(inst, I_from_)):
               pass
            elif (isinstance(inst, Arg)):
               ch.WARNING("ARG before FROM not yet supported; see issue #779")
               return
            else:
               ch.FATAL("first instruction must be ARG or FROM")
         inst.init(self.inst_prev)
         try:
            self.miss_ct = inst.prepare(self.miss_ct)
         except Instruction_Ignored:
            return
         if (inst.miss):
            if (self.miss_ct == 1):
               inst.checkout_for_build()
            inst.execute()
            if (inst.image_i >= 0):
               inst.metadata_update()
            inst.commit()
         self.inst_prev = inst
         self.instruction_total_ct += 1


## Instruction classes ##

class Instruction(abc.ABC):

   __slots__ = ("git_hash",     # Git commit where sid was found
                "image",
                "image_alias",
                "image_i",
                "lineno",
                "options",      # consumed
                "options_str",  # saved at instantiation
                "parent",
                "sid",
                "tree")

   def __init__(self, tree):
      """Note: When this is called, all we know about the instruction is
         what's in the parse tree. In particular, you must not call
         variables_sub() here."""
      self.lineno = tree.meta.line
      self.options = {}
      for st in ch.tree_children(tree, "option"):
         k = ch.tree_terminal(st, "OPTION_KEY")
         v = ch.tree_terminal(st, "OPTION_VALUE")
         if (k in self.options):
            ch.FATAL("%3d %s: repeated option --%s"
                     % (self.lineno, self.str_name, k))
         self.options[k] = v
      self.options_str = " ".join("--%s=%s" % (k,v)
                                  for (k,v) in self.options.items())
      self.tree = tree
      # These are set in init().
      self.image = None
      self.parent = None
      self.image_alias = None
      self.image_i = None

   @property
   def env_arg(self):
      if (self.image is None):
         assert False, "unimplemented"  # return dict()
      else:
         return self.image.metadata["arg"]

   @property
   def env_build(self):
      return { **self.env_arg, **self.env_env }

   @property
   def env_env(self):
      if (self.image is None):
         assert False, "unimplemented"  # return dict()
      else:
         return self.image.metadata["env"]

   @property
   def first_p(self):
      """Return True if the first instruction, False otherwise. WARNING: Do
         not just check that attribute “parent” is None, because some first
         instructions do set their parent."""
      return (self.parent is None or self.parent is self)

   @property
   def miss(self):
      return (self.git_hash is None)

   @property
   def shell(self):
      if (self.image is None):
         assert False, "unimplemented"  # return ["/bin/false"]
      else:
         return self.image.metadata["shell"]

   @shell.setter
   def shell(self, x):
      self.image.metadata["shell"] = x

   @property
   def sid_input(self):
      return str(self).encode("UTF-8")

   @property
   @abc.abstractmethod
   def str_(self):
      ...

   @property
   def str_name(self):
      return self.__class__.__name__.split("_")[1].upper()

   @property
   def str_log(self):
      return ("%3s%s %s" % (self.lineno, bu.cache.status_char(self.miss), self))

   @property
   def workdir(self):
      return ch.Path(self.image.metadata["cwd"])

   @workdir.setter
   def workdir(self, x):
      self.image.metadata["cwd"] = str(x)

   def __str__(self):
      options = self.options_str
      if (options != ""):
         options = " " + options
      return "%s %s%s" % (self.str_name, options, self.str_)

   def chdir(self, path):
      if (path.startswith("/")):
         self.workdir = ch.Path(path)
      else:
         self.workdir //= path

   def checkout(self, base_image=None):
      bu.cache.checkout(self.image, self.git_hash, base_image)

   def checkout_for_build(self, base_image=None):
      self.parent.checkout(base_image)
      global fakeroot_config
      fakeroot_config = fakeroot.detect(self.image.unpack_path,
                                        cli.force, cli.no_force_detect)

   def commit(self):
      path = self.image.unpack_path
      self.git_hash = bu.cache.commit(path, self.sid, str(self))

   def ready(self):
      bu.cache.ready(self.image)

   def execute(self):
      """Do what the instruction says. At this point, the unpack directory is
         all ready to go. Thus, the method is cache-ignorant."""
      pass

   def ignore(self):
      ch.INFO(self.str_log)
      raise Instruction_Ignored()

   def init(self, parent):
      """Initialize attributes defining this instruction's context, much of
         which is not available until the previous instruction is processed.
         After this is called, the instruction has a valid image and parent
         instruction, unless it's the first instruction, in which case
         prepare() does the initialization."""
      # Separate from prepare() because subclasses shouldn't need to override
      # it. If a subclass doesn't like the result, it can just change things
      # in prepare().
      self.parent = parent
      if (self.parent is None):
         self.image_i = -1
      else:
         self.image = self.parent.image
         self.image_alias = self.parent.image_alias
         self.image_i = self.parent.image_i

   def metadata_update(self):
      self.image.metadata["history"].append(
         { "created": ch.now_utc_iso8601(),
           "created_by": "%s %s" % (self.str_name, self.str_)})
      self.image.metadata_save()

   def options_assert_empty(self):
      try:
         k = next(iter(self.options.keys()))
         ch.FATAL("%s: invalid option --%s" % (self.str_name, k))
      except StopIteration:
         pass

   def prepare(self, miss_ct):
      """Set up for execution; parent is the parent instruction and miss_ct is
         the number of misses in this stage so far. Returns the new number of
         misses; usually miss_ct if this instruction hit or miss_ct + 1 if it
         missed. Some instructions (e.g., FROM) resets the miss count.
         Announce self as soon as hit/miss status is known, hopefully before
         doing anything complicated or time-consuming.

         Typically, subclasses will set up enough state for self.sid_input to
         be valid, then call super().prepare().

         WARNING: Instructions that modify image metadata (at this writing,
         ARG ENV FROM SHELL WORKDIR) must do so here, not in execute(), so
         that metadata is available to late instructions even on cache hit."""
      self.sid = bu.cache.sid_from_parent(self.parent.sid, self.sid_input)
      self.git_hash = bu.cache.find_sid(self.sid, self.image.ref.for_path)
      ch.INFO(self.str_log)
      return miss_ct + int(self.miss)

   def unsupported_forever_warn(self, msg):
      ch.WARNING("not supported, ignored: %s %s" % (self.str_name, msg))

   def unsupported_yet_warn(self, msg, issue_no):
      ch.WARNING("not yet supported, ignored: issue #%d: %s %s"
                 % (issue_no, self.str_name, msg))

   def unsupported_yet_fatal(self, msg, issue_no):
      ch.FATAL("not yet supported: issue #%d: %s %s"
               % (issue_no, self.str_name, msg))


class Instruction_Ignored(Exception):
   __slots__ = ()
   pass


class Instruction_Unsupported(Instruction):

   __slots__ = ()

   @property
   def str_(self):
      return "(unsupported)"

   @property
   def miss(self):
      return None


class Instruction_Supported_Never(Instruction_Unsupported):

   __slots__ = ()

   def prepare(self, *args):
      self.unsupported_forever_warn("instruction")
      self.ignore()


class Arg(Instruction):

   __slots__ = ("key",
                "value")

   def __init__(self, *args):
      super().__init__(*args)
      self.key = ch.tree_terminal(self.tree, "WORD", 0)
      if (self.key in cli.build_arg):
         self.value = cli.build_arg[self.key]
         del cli.build_arg[self.key]
      else:
         self.value = self.value_default()

   @property
   def sid_input(self):
      if (self.key in ch.ARGS_MAGIC):
         return (self.str_name + self.key).encode("UTF-8")
      else:
         return super().sid_input

   @property
   def str_(self):
      s = "%s=" % self.key
      if (self.value is not None):
         s += "'%s'" % self.value
      if (self.key in ch.ARGS_MAGIC):
         s += " [special]"
      return s

   def prepare(self, *args):
      if (self.value is not None):
         self.value = variables_sub(self.value, self.env_build)
         self.env_arg[self.key] = self.value
      return super().prepare(*args)


class I_arg_bare(Arg):

   __slots__ = ()

   def value_default(self):
      return None


class I_arg_equals(Arg):

   __slots__ = ()

   def value_default(self):
      v = ch.tree_terminal(self.tree, "WORD", 1)
      if (v is None):
         v = unescape(ch.tree_terminal(self.tree, "STRING_QUOTED"))
      return v


class I_copy(Instruction):

   # Note: The Dockerfile specification for COPY is complex, messy,
   # inexplicably different from cp(1), and incomplete. We try to be
   # bug-compatible with Docker but probably are not 100%. See the FAQ.
   #
   # Because of these weird semantics, none of this abstracted into a general
   # copy function. I don't want people calling it except from here.

   __slots__ = ("dst",
                "dst_raw",
                "from_",
                "src_metadata",
                "srcs",
                "srcs_raw")

   def __init__(self, *args):
      super().__init__(*args)
      self.from_ = self.options.pop("from", None)
      if (self.from_ is not None):
         try:
            self.from_ = int(self.from_)
         except ValueError:
            pass
      # No subclasses, so check what parse tree matched.
      if (ch.tree_child(self.tree, "copy_shell") is not None):
         args = list(ch.tree_child_terminals(self.tree, "copy_shell", "WORD"))
      elif (ch.tree_child(self.tree, "copy_list") is not None):
         args = list(ch.tree_child_terminals(self.tree, "copy_list",
                                             "STRING_QUOTED"))
         for i in range(len(args)):
            args[i] = args[i][1:-1]  # strip quotes
      else:
         assert False, "unreachable code reached"
      self.srcs_raw = args[:-1]
      self.dst_raw = args[-1]

   @property
   def sid_input(self):
      return super().sid_input + self.src_metadata

   @property
   def str_(self):
      return "%s -> %s" % (self.srcs_raw, repr(self.dst))

   def copy_src_dir(self, src, dst):
      """Copy the contents of directory src, named by COPY, either explicitly
         or with wildcards, to dst. src might be a symlink, but dst is a
         canonical path. Both must be at the top level of the COPY
         instruction; i.e., this function must not be called recursively. dst
         must exist already and be a directory. Unlike subdirectories, the
         metadata of dst will not be altered to match src."""
      def onerror(x):
         ch.FATAL("can't scan directory: %s: %s" % (x.filename, x.strerror))
      # Use Path objects in this method because the path arithmetic was
      # getting too hard with strings.
      src = ch.Path(os.path.realpath(src))
      dst = ch.Path(dst)
      assert (os.path.isdir(src) and not os.path.islink(src))
      assert (os.path.isdir(dst) and not os.path.islink(dst))
      ch.DEBUG("copying named directory: %s -> %s" % (src, dst))
      for (dirpath, dirnames, filenames) in os.walk(src, onerror=onerror):
         dirpath = ch.Path(dirpath)
         subdir = dirpath.relative_to(src)
         dst_dir = dst // subdir
         # dirnames can contain symlinks, which we handle as files, so we'll
         # rebuild it; the walk will not descend into those "directories".
         dirnames2 = dirnames.copy()  # shallow copy
         dirnames[:] = list()         # clear in place
         for d in dirnames2:
            d = ch.Path(d)
            src_path = dirpath // d
            dst_path = dst_dir // d
            ch.TRACE("dir: %s -> %s" % (src_path, dst_path))
            if (os.path.islink(src_path)):
               filenames.append(d)  # symlink, handle as file
               ch.TRACE("symlink to dir, will handle as file")
               continue
            else:
               dirnames.append(d)   # directory, descend into later
            # If destination exists, but isn't a directory, remove it.
            if (os.path.exists(dst_path)):
               if (os.path.isdir(dst_path) and not os.path.islink(dst_path)):
                  ch.TRACE("dst_path exists and is a directory")
               else:
                  ch.TRACE("dst_path exists, not a directory, removing")
                  ch.unlink(dst_path)
            # If destination directory doesn't exist, create it.
            if (not os.path.exists(dst_path)):
               ch.TRACE("mkdir dst_path")
               ch.ossafe(os.mkdir, "can't mkdir: %s" % dst_path, dst_path)
            # Copy metadata, now that we know the destination exists and is a
            # directory.
            ch.ossafe(shutil.copystat,
                      "can't copy metadata: %s -> %s" % (src_path, dst_path),
                      src_path, dst_path, follow_symlinks=False)
         for f in filenames:
            f = ch.Path(f)
            src_path = dirpath // f
            dst_path = dst_dir // f
            ch.TRACE("file or symlink via copy2: %s -> %s"
                      % (src_path, dst_path))
            if (not (os.path.isfile(src_path) or os.path.islink(src_path))):
               ch.FATAL("can't COPY: unknown file type: %s" % src_path)
            if (os.path.exists(dst_path)):
               ch.TRACE("destination exists, removing")
               if (os.path.isdir(dst_path) and not os.path.islink(dst_path)):
                  ch.rmtree(dst_path)
               else:
                  ch.unlink(dst_path)
            ch.copy2(src_path, dst_path, follow_symlinks=False)

   def copy_src_file(self, src, dst):
      """Copy file src, named by COPY either explicitly or with wildcards, to
         dst. src might be a symlink, but dst is a canonical path. Both must
         be at the top level of the COPY instruction; i.e., this function must
         not be called recursively. If dst is a directory, file should go in
         that directory named src (i.e., the directory creation magic has
         already happened)."""
      assert (os.path.isfile(src))
      assert (   not os.path.exists(dst)
              or (os.path.isdir(dst) and not os.path.islink(dst))
              or (os.path.isfile(dst) and not os.path.islink(dst)))
      ch.DEBUG("copying named file: %s -> %s" % (src, dst))
      ch.copy2(src, dst, follow_symlinks=True)

   def dest_realpath(self, unpack_path, dst):
      """Return the canonicalized version of path dst within (canonical) image
        path unpack_path. We can't use os.path.realpath() because if dst is
        an absolute symlink, we need to use the *image's* root directory, not
        the host. Thus, we have to resolve symlinks manually."""
      unpack_path = ch.Path(unpack_path)
      dst_canon = ch.Path(unpack_path)
      dst = ch.Path(dst)
      dst_parts = list(reversed(dst.parts))  # easier to operate on end of list
      iter_ct = 0
      while (len(dst_parts) > 0):
         iter_ct += 1
         if (iter_ct > 100):  # arbitrary
            ch.FATAL("can't COPY: too many path components")
         ch.TRACE("current destination: %d %s" % (iter_ct, dst_canon))
         #ch.TRACE("parts remaining: %s" % dst_parts)
         part = dst_parts.pop()
         if (part == "/" or part == "//"):  # 3 or more slashes yields "/"
            ch.TRACE("skipping root")
            continue
         cand = dst_canon // part
         ch.TRACE("checking: %s" % cand)
         if (not cand.is_symlink()):
            ch.TRACE("not symlink")
            dst_canon = cand
         else:
            target = ch.Path(os.readlink(cand))
            ch.TRACE("symlink to: %s" % target)
            assert (len(target.parts) > 0)  # POSIX says no empty symlinks
            if (target.is_absolute()):
               ch.TRACE("absolute")
               dst_canon = ch.Path(unpack_path)
            else:
               ch.TRACE("relative")
            dst_parts.extend(reversed(target.parts))
      return dst_canon

   def execute(self):
      # Locate the destination.
      unpack_canon = os.path.realpath(self.image.unpack_path)
      if (self.dst.startswith("/")):
         dst = ch.Path(self.dst)
      else:
         dst = self.workdir // self.dst
      ch.VERBOSE("destination, as given: %s" % dst)
      dst_canon = self.dest_realpath(unpack_canon, dst) # strips trailing slash
      ch.VERBOSE("destination, canonical: %s" % dst_canon)
      if (not os.path.commonpath([dst_canon, unpack_canon])
              .startswith(unpack_canon)):
         ch.FATAL("can't COPY: destination not in image: %s" % dst_canon)
      # Create the destination directory if needed.
      if (   self.dst.endswith("/")
          or len(self.srcs) > 1
          or os.path.isdir(self.srcs[0])):
         if (not os.path.exists(dst_canon)):
            ch.mkdirs(dst_canon)
         elif (not os.path.isdir(dst_canon)):  # not symlink b/c realpath()
            ch.FATAL("can't COPY: not a directory: %s" % dst_canon)
      # Copy each source.
      for src in self.srcs:
         if (os.path.isfile(src)):
            self.copy_src_file(src, dst_canon)
         elif (os.path.isdir(src)):
            self.copy_src_dir(src, dst_canon)
         else:
            ch.FATAL("can't COPY: unknown file type: %s" % src)

   def prepare(self, miss_ct):
      def stat_bytes(path, links=False):
         st = ch.stat_(path, links=links)
         return path.encode("UTF-8") + struct.pack("=HQQQ",
                                                   st.st_mode,
                                                   st.st_size,
                                                   st.st_mtime_ns,
                                                   st.st_ctime_ns)
      # Error checking.
      if (cli.context == "-"):
         ch.FATAL("can't COPY: no context because \"-\" given")
      if (len(self.srcs_raw) < 1):
         ch.FATAL("can't COPY: must specify at least one source")
      # Complain about unsupported stuff.
      if (self.options.pop("chown", False)):
         self.unsupported_forever_warn("--chown")
      # Any remaining options are invalid.
      self.options_assert_empty()
      # Find the context directory.
      if (self.from_ is None):
         context = cli.context
      else:
         if (self.from_ == self.image_i or self.from_ == self.image_alias):
            ch.FATAL("COPY --from: stage %s is the current stage" % self.from_)
         if (not self.from_ in images):
            # FIXME: Would be nice to also report if a named stage is below.
            if (isinstance(self.from_, int) and self.from_ < image_ct):
               if (self.from_ < 0):
                  ch.FATAL("COPY --from: invalid negative stage index %d"
                           % self.from_)
               else:
                  ch.FATAL("COPY --from: stage %d does not exist yet"
                           % self.from_)
            else:
               ch.FATAL("COPY --from: stage %s does not exist" % self.from_)
         context = images[self.from_].unpack_path
      context_canon = os.path.realpath(context)
      ch.VERBOSE("context: %s" % context)
      # Expand sources.
      self.srcs = list()
      for src in [variables_sub(i, self.env_build) for i in self.srcs_raw]:
         matches = glob.glob("%s/%s" % (context, src))  # glob can't take Path
         if (len(matches) == 0):
            ch.FATAL("can't copy: not found: %s" % src)
         for i in matches:
            self.srcs.append(i)
            ch.VERBOSE("source: %s" % i)
      # Expand destination.
      self.dst = variables_sub(self.dst_raw, self.env_build)
      # Validate sources are within context directory. (Can't convert to
      # canonical paths yet because we need the source path as given.)
      for src in self.srcs:
         src_canon = os.path.realpath(src)
         if (not os.path.commonpath([src_canon, context_canon])
                 .startswith(context_canon)):
            ch.FATAL("can't COPY from outside context: %s" % src)
      # Gather metadata for hashing.
      # FIXME: Locale issues related to sorting?
      self.src_metadata = bytearray()
      for src in self.srcs:
         self.src_metadata += stat_bytes(src, links=True)
         if (os.path.isdir(src)):
            for (dir_, dirs, files) in os.walk(src):
               self.src_metadata += stat_bytes(dir_)
               for f in sorted(files):
                  self.src_metadata += stat_bytes(os.path.join(dir_, f))
               dirs.sort()
      # Pass on to superclass.
      return super().prepare(miss_ct)


class I_directive(Instruction_Supported_Never):

   __slots__ = ()

   @property
   def str_name(self):
      return "#%s" % ch.tree_terminal(self.tree, "DIRECTIVE_NAME")

   def prepare(self, *args):
      ch.WARNING("not supported, ignored: parser directives")
      self.ignore()


class Env(Instruction):

   __slots__ = ("key",
                "value")

   @property
   def str_(self):
      return "%s='%s'" % (self.key, self.value)

   def execute(self):
      with ch.open_(self.image.unpack_path // "/ch/environment", "wt") \
           as fp:
         for (k, v) in self.env_env.items():
            print("%s=%s" % (k, v), file=fp)

   def prepare(self, *args):
      self.value = variables_sub(unescape(self.value), self.env_build)
      self.env_env[self.key] = self.value
      return super().prepare(*args)


class I_env_equals(Env):

   __slots__ = ()

   def __init__(self, *args):
      super().__init__(*args)
      self.key = ch.tree_terminal(self.tree, "WORD", 0)
      self.value = ch.tree_terminal(self.tree, "WORD", 1)
      if (self.value is None):
         self.value = ch.tree_terminal(self.tree, "STRING_QUOTED")


class I_env_space(Env):

   __slots__ = ()

   def __init__(self, *args):
      super().__init__(*args)
      self.key = ch.tree_terminal(self.tree, "WORD")
      self.value = ch.tree_terminals_cat(self.tree, "LINE_CHUNK")


class I_from_(Instruction):

   __slots__ = ("alias",
                "base_image")

   def __init__(self, *args):
      super().__init__(*args)
      self.base_image = ch.Image(ch.Image_Ref(ch.tree_child(self.tree,
                                                            "image_ref")))
      self.alias = ch.tree_child_terminal(self.tree, "from_alias",
                                          "IR_PATH_COMPONENT")

   # Not meaningful for FROM.
   sid_input = None

   @property
   def str_(self):
      alias = " AS %s" % self.alias if self.alias else ""
      return "%s%s" % (self.base_image.ref, alias)

   def checkout_for_build(self):
      assert (isinstance(bu.cache, bu.Disabled_Cache))
      super().checkout_for_build(self.base_image)

   def metadata_update(self, *args):
      # FROM doesn’t update metadata because it never misses when the cache is
      # enabled, so this would never be called, and we want disabled results
      # to be the same. In particular, FROM does not generate history entries.
      pass

   def prepare(self, miss_ct):
      # FROM is special because its preparation involves opening a new stage
      # and closing the previous if there was one. Because of this, the actual
      # parent is the last instruction of the base image.
      #
      # Validate instruction.
      if (self.options.pop("platform", False)):
         self.unsupported_yet_fatal("--platform", 778)
      self.options_assert_empty()
      # Update context.
      self.image_i += 1
      self.image_alias = self.alias
      if (self.image_i == image_ct - 1):
         # Last image; use tag unchanged.
         tag = cli.tag
      elif (self.image_i > image_ct - 1):
         # Too many images!
         ch.FATAL("expected %d stages but found at least %d"
                  % (image_ct, self.image_i + 1))
      else:
         # Not last image; append stage index to tag.
         tag = "%s/_stage%d" % (cli.tag, self.image_i)
      self.image = ch.Image(ch.Image_Ref(tag))
      images[self.image_i] = self.image
      if (self.image_alias is not None):
         images[self.image_alias] = self.image
      ch.VERBOSE("image path: %s" % self.image.unpack_path)
      # FROM doesn’t have a meaningful parent because it’s opening a new
      # stage, so act as own parent.
      self.parent = self
      # More error checking.
      if (str(self.image.ref) == str(self.base_image.ref)):
         ch.FATAL("output image ref same as FROM: %s" % self.base_image.ref)
      # Close previous stage if needed.
      if (not self.first_p and miss_ct == 0):
         # While there haven't been any misses so far, we do need to check out
         # the previous stage (a) to read its metadata and (b) in case there's
         # a COPY later. This will still be fast most of the time since the
         # correct branch is likely to be checked out already.
         self.parent.checkout()
         self.parent.ready()
      # Pull base image if needed.
      (self.sid, self.git_hash) = bu.cache.find_image(self.base_image)
      unpack_no_git = (    self.base_image.unpack_exist_p
                       and not self.base_image.unpack_cache_linked)
      ch.INFO(self.str_log)  # announce before we start pulling
      # FIXME: shouldn't know or care whether build cache is enabled here.
      if (self.miss):
         if (unpack_no_git):
            # Use case is mostly images built by old ch-image still in storage.
            if (not isinstance(bu.cache, bu.Disabled_Cache)):
               ch.WARNING("base image only exists non-cached; adding to cache")
            (self.sid, self.git_hash) = bu.cache.adopt(self.base_image)
         else:
            (self.sid, self.git_hash) = bu.cache.pull_lazy(self.base_image)
      elif (unpack_no_git):
         ch.WARNING("base image also exists non-cached; using cache")
      # Load metadata
      self.image.metadata_load(self.base_image)
      # Done.
      return int(self.miss)  # will still miss in disabled mode

   def execute(self):
      # Everything happens in prepare().
      pass


class Run(Instruction):

   __slots__ = ("cmd")

   # FIXME: This causes spurious misses because it adds the force bit to *all*
   # RUN instructions, not just those that actually were modified (i.e, any
   # RUN instruction will miss the equivalent RUN with --force inverted). But
   # we don't know know if an instruction needs modifications until the result
   # is checked out, which happens after we check the cache. See issue #FIXME.
   @property
   def str_name(self):
      return super().str_name + (".F" if cli.force else "")

   def execute(self):
      rootfs = self.image.unpack_path
      fakeroot_config.init_maybe(rootfs, self.cmd, self.env_build)
      cmd = fakeroot_config.inject_run(self.cmd)
      exit_code = ch.ch_run_modify(rootfs, cmd, self.env_build, self.workdir,
                                   cli.bind, fail_ok=True)
      if (exit_code != 0):
         msg = "build failed: RUN command exited with %d" % exit_code
         if (cli.force):
            if (isinstance(fakeroot_config, fakeroot.Fakeroot_Noop)):
               ch.FATAL(msg, "--force specified, but no suitable config found")
            else:
               ch.FATAL(msg)  # --force inited OK but the build still failed
         elif (not cli.no_force_detect):
            if (fakeroot_config.init_done):
               ch.FATAL(msg, "--force may fix it")
            else:
               ch.FATAL(msg, "current version of --force wouldn't help")
         assert False, "unreachable code reached"


class I_run_exec(Run):

   __slots__ = ()

   @property
   def str_(self):
      return json.dumps(self.cmd)  # double quotes, shlex.quote is less verbose

   def prepare(self, *args):
      self.cmd = [    variables_sub(unescape(i), self.env_build)
                  for i in ch.tree_terminals(self.tree, "STRING_QUOTED")]
      return super().prepare(*args)


class I_run_shell(Run):

   # Note re. line continuations and whitespace: Whitespace before the
   # backslash is passed verbatim to the shell, while the newline and any
   # whitespace between the newline and baskslash are deleted.

   __slots__ = ("_str_")

   @property
   def str_(self):
      return self._str_  # can't replace abstract property with attribute

   def prepare(self, *args):
      cmd = ch.tree_terminals_cat(self.tree, "LINE_CHUNK")
      self.cmd = self.shell + [cmd]
      self._str_ = cmd
      return super().prepare(*args)


class I_shell(Instruction):

   @property
   def str_(self):
      return str(self.shell)

   def prepare(self, *args):
      self.shell = [variables_sub(unescape(i), self.env_build)
                    for i in ch.tree_terminals(self.tree, "STRING_QUOTED")]
      return super().prepare(*args)


class I_workdir(Instruction):

   __slots__ = ("path")

   @property
   def str_(self):
      return self.path

   def execute(self):
      ch.mkdirs(self.image.unpack_path // self.workdir)

   def prepare(self, *args):
      self.path = variables_sub(ch.tree_terminals_cat(self.tree, "LINE_CHUNK"),
                                self.env_build)
      self.chdir(self.path)
      return super().prepare(*args)


class I_uns_forever(Instruction_Supported_Never):

   __slots__ = ("name")

   def __init__(self, *args):
      super().__init__(*args)
      self.name = ch.tree_terminal(self.tree, "UNS_FOREVER")

   @property
   def str_name(self):
      return self.name


class I_uns_yet(Instruction_Unsupported):

   __slots__ = ("issue_no",
                "name")

   def __init__(self, *args):
      super().__init__(*args)
      self.name = ch.tree_terminal(self.tree, "UNS_YET")
      self.issue_no = { "ADD":         782,
                        "CMD":         780,
                        "ENTRYPOINT":  780,
                        "LABEL":       781,
                        "ONBUILD":     788 }[self.name]

   @property
   def str_name(self):
      return self.name

   def prepare(self, *args):
      self.unsupported_yet_warn("instruction", self.issue_no)
      self.ignore()


## Supporting classes ##

class Environment:
   """The state we are in: environment variables, working directory, etc. Most
      of this is just passed through from the image metadata."""

   # FIXME:
   # - problem:
   #   1. COPY (at least) needs a valid build environment to figure out if it's
   #      a hit or miss, which happens in prepare()
   #   2. no files from the image are available in prepare(), so we can't read
   #      image metadata then
   #      - could get it from Git if needed, but that seems complicated
   # - valid during prepare() and execute() but not __init__()
   #   - in particular, don't variables_sub() in __init__()
   # - instructions that update it need to change the env object in prepare()
   #   - WORKDIR SHELL ARG ENV
   #   - FROM
   #     - global images and image_i makes this harder because we need to read
   #       the metadata of image_i - 1
   #       - solution: remove those two globals? instructions grow image and
   #         image_i attributes?


## Supporting functions ###

def variables_sub(s, variables):
   # FIXME: This should go in the grammar rather than being a regex kludge.
   #
   # Dockerfile spec does not say what to do if substituting a value that's
   # not set. We ignore those subsitutions. This is probably wrong (the shell
   # substitutes the empty string).
   for (k, v) in variables.items():
      # FIXME: remove when issue #774 is fixed
      m = re.search(r"(?<!\\)\${.+?:[+-].+?}", s)
      if (m is not None):
         ch.FATAL("modifiers ${foo:+bar} and ${foo:-bar} not yet supported (issue #774)")
      s = re.sub(r"(?<!\\)\${?%s}?" % k, v, s)
   return s

def unescape(sl):
   # FIXME: This is also ugly and should go in the grammar.
   #
   # The Dockerfile spec does not precisely define string escaping, but I'm
   # guessing it's the Go rules. You will note that we are using Python rules.
   # This is wrong but close enough for now (see also gripe in previous
   # paragraph).
   if (    not sl.startswith('"')                          # no start quote
       and (not sl.endswith('"') or sl.endswith('\\"'))):  # no end quote
      sl = '"%s"' % sl
   assert (len(sl) >= 2 and sl[0] == '"' and sl[-1] == '"' and sl[-2:] != '\\"')
   return ast.literal_eval(sl)
