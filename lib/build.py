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
import filesystem as fs
import force
import image as im


## Globals ##

# ARG values that are set before FROM.
argfrom = {}

# Namespace from command line arguments. FIXME: be more tidy about this ...
cli = None

# --force injector object (initialized to something meaningful during FROM).
forcer = None

# Images that we are building. Each stage gets its own image. In this
# dictionary, an image appears exactly once or twice. All images appear with
# an int key counting stages up from zero. Images with a name (e.g., “FROM ...
# AS foo”) have a second string key of the name.
images = dict()
# Number of stages. This is obtained by counting FROM instructions in the
# parse tree, so we can use it for error checking.
image_ct = None


## Imports not in standard library ##

# See charliecloud.py for the messy import of this.
lark = im.lark


## Exceptions ##

class Instruction_Ignored(Exception): pass


## Main ##

def main(cli_):

   # CLI namespace. :P
   global cli
   cli = cli_

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
      elif (ext_last in ("df", "dockerfile")):
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

   # --force and friends.
   if (cli.force_cmd and cli.force == "fakeroot"):
      ch.FATAL("--force-cmd and --force=fakeroot are incompatible")
   if (not cli.force_cmd):
      cli.force_cmd = force.FORCE_CMD_DEFAULT
   else:
      cli.force = "seccomp"
      # convert cli.force_cmd to parsed dict
      force_cmd = dict()
      for line in cli.force_cmd:
         (cmd, args) = force.force_cmd_parse(line)
         force_cmd[cmd] = args
      cli.force_cmd = force_cmd
   ch.VERBOSE("force mode: %s" % cli.force)
   if (cli.force == "seccomp"):
      for (cmd, args) in cli.force_cmd.items():
         ch.VERBOSE("force command: %s" % ch.argv_to_string([cmd] + args))
   if (    cli.force == "seccomp"
       and ch.cmd([ch.CH_BIN + "/ch-run", "--feature=seccomp"],
                  fail_ok=True) != 0):
      ch.FATAL("ch-run was not built with seccomp(2) support")

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
   # typical looking URL e.g. “https://...” or also something like
   # “git@github.com:...”. The line noise in the second line of the regex is
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
      text = ch.ossafe(sys.stdin.read, "can’t read stdin")
   elif (not os.path.isdir(cli.context)):
      ch.FATAL("context must be a directory: %s" % cli.context)
   else:
      fp = fs.Path(cli.file).open_("rt")
      text = ch.ossafe(fp.read, "can’t read: %s" % cli.file)
      ch.close_(fp)

   # Parse it.
   parser = lark.Lark(im.GRAMMAR_DOCKERFILE, parser="earley",
                      propagate_positions=True, tree_class=im.Tree)
   # Avoid Lark issue #237: lark.exceptions.UnexpectedEOF if the file does not
   # end in newline.
   text += "\n"
   try:
      tree = parser.parse(text)
   except lark.exceptions.UnexpectedInput as x:
      ch.VERBOSE(x)  # noise about what was expected in the grammar
      ch.FATAL("can’t parse: %s:%d,%d\n\n%s"
               % (cli.file, x.line, x.column, x.get_context(text, 39)))
   ch.VERBOSE(tree.pretty())

   # Sometimes we exit after parsing.
   if (cli.parse_only):
      ch.exit(0)

   # Count the number of stages (i.e., FROM instructions)
   global image_ct
   image_ct = sum(1 for i in tree.children_("from_"))

   # Traverse the tree and do what it says.
   #
   # We don’t actually care whether the tree is traversed breadth-first or
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

   # Print summary & we’re done.
   if (ml.instruction_total_ct == 0):
      ch.FATAL("no instructions found: %s" % cli.file)
   assert (ml.inst_prev.image_i + 1 == image_ct)  # should’ve errored already
   if (cli.force and ml.miss_ct != 0):
      ch.INFO("--force=%s: modified %d RUN instructions"
              % (cli.force, forcer.run_modified_ct))
   ch.INFO("grown in %d instructions: %s"
           % (ml.instruction_total_ct, ml.inst_prev.image))
   # FIXME: remove when we’re done encouraging people to use the build cache.
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
            if (not (isinstance(inst, I_directive)
                  or isinstance(inst, I_from_)
                  or isinstance(inst, Instruction_No_Image))):
               ch.FATAL("first instruction must be ARG or FROM")
         inst.init(self.inst_prev)
         # The three announce_maybe() calls are clunky but I couldn’t figure
         # out how to avoid the repeats.
         try:
            self.miss_ct = inst.prepare(self.miss_ct)
            inst.announce_maybe()
         except Instruction_Ignored:
            inst.announce_maybe()
            return
         except ch.Fatal_Error:
            inst.announce_maybe()
            raise
         if (inst.miss):
            if (self.miss_ct == 1):
               inst.checkout_for_build()
            try:
               inst.execute()
            except ch.Fatal_Error:
               inst.rollback()
               raise
            if (inst.image_i >= 0):
               inst.metadata_update()
            inst.commit()
         self.inst_prev = inst
         self.instruction_total_ct += 1


## Instruction classes ##

class Instruction(abc.ABC):

   __slots__ = ("announced_p",
                "commit_files",  # modified files; default: anything
                "git_hash",      # Git commit where sid was found
                "image",
                "image_alias",
                "image_i",
                "lineno",
                "options",       # consumed
                "options_str",   # saved at instantiation
                "parent",
                "sid",
                "tree")

   def __init__(self, tree):
      """Note: When this is called, all we know about the instruction is
         what’s in the parse tree. In particular, you must not call
         ch.variables_sub() here."""
      self.announced_p = False
      self.commit_files = set()
      self.git_hash = bu.GIT_HASH_UNKNOWN
      self.lineno = tree.meta.line
      self.options = dict()
      # saving options with only 1 saved value
      for st in tree.children_("option"):
         k = st.terminal("OPTION_KEY")
         v = st.terminal("OPTION_VALUE")
         if (k in self.options):
            ch.FATAL("%3d %s: repeated option --%s"
                     % (self.lineno, self.str_name, k))
         self.options[k] = v

      # saving keypair options in a dictionary
      for st in tree.children_("option_keypair"):
         k = st.terminal("OPTION_KEY")
         s = st.terminal("OPTION_VAR")
         v = st.terminal("OPTION_VALUE")
         # assuming all key pair options allow multiple options
         self.options.setdefault(k, {}).update({s: v})

      ol = list()
      for (k, v) in self.options.items():
         if (isinstance(v, dict)):
            for (k2, v) in v.items():
               ol.append("--%s=%s=%s" % (k, k2, v))
         else:
            ol.append("--%s=%s" % (k, v))
      self.options_str = " ".join(ol)
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
   def miss(self):
      """This is actually a three-valued property:

           1. True  => miss
           2. False => hit
           3. None  => unknown or n/a"""
      if (self.git_hash == bu.GIT_HASH_UNKNOWN):
         return None
      else:
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
   def status_char(self):
      return bu.cache.status_char(self.miss)

   @property
   @abc.abstractmethod
   def str_(self):
      ...

   @property
   def str_name(self):
      return self.__class__.__name__.split("_")[1].upper()

   @property
   def workdir(self):
      return fs.Path(self.image.metadata["cwd"])

   @workdir.setter
   def workdir(self, x):
      self.image.metadata["cwd"] = str(x)

   def __str__(self):
      options = self.options_str
      if (options != ""):
         options = " " + options
      return "%s%s %s" % (self.str_name, options, self.str_)

   def announce_maybe(self):
      "Announce myself if I haven’t already been announced."
      if (not self.announced_p):
         ch.INFO("%3s%s %s" % (self.lineno, self.status_char, self))
         self.announced_p = True

   def chdir(self, path):
      if (path.is_absolute()):
         self.workdir = path
      else:
         self.workdir //= path

   def checkout(self, base_image=None):
      bu.cache.checkout(self.image, self.git_hash, base_image)

   def checkout_for_build(self, base_image=None):
      self.parent.checkout(base_image)
      global forcer
      forcer = force.new(self.image.unpack_path, cli.force, cli.force_cmd)

   def commit(self):
      path = self.image.unpack_path
      self.git_hash = bu.cache.commit(path, self.sid, str(self),
                                      self.commit_files)

   def ready(self):
      bu.cache.ready(self.image)

   def execute(self):
      """Do what the instruction says. At this point, the unpack directory is
         all ready to go. Thus, the method is cache-ignorant."""
      pass

   def init(self, parent):
      """Initialize attributes defining this instruction’s context, much of
         which is not available until the previous instruction is processed.
         After this is called, the instruction has a valid image and parent
         instruction, unless it’s the first instruction, in which case
         prepare() does the initialization."""
      # Separate from prepare() because subclasses shouldn’t need to override
      # it. If a subclass doesn’t like the result, it can just change things
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

         Gotchas:

           1. Announcing the instruction: Subclasses that are fast can let the
              caller announce. However, subclasses that consume non-trivial
              time in prepare() should call announce_maybe() as soon as they
              know hit/miss status.

           2. Errors: Calling ch.FATAL() normally exits immediately, but here
              this often happens before the instruction has been announced
              (see issue #1486). Therefore, the caller catches Fatal_Error,
              announces, and then re-raises.

           3. Modifying image metadata: Instructions like ARG, ENV, FROM,
              LABEL, SHELL, and WORKDIR must modify metadata here, not in
              execute(), so it’s available to later instructions even on
              cache hit."""
      self.sid = bu.cache.sid_from_parent(self.parent.sid, self.sid_input)
      self.git_hash = bu.cache.find_sid(self.sid, self.image.ref.for_path)
      return miss_ct + int(self.miss)

   def rollback(self):
      """Discard everything done by execute(), which may have completed
         partially, fully, or not at all."""
      bu.cache.rollback(self.image.unpack_path)

   def unsupported_forever_warn(self, msg):
      ch.WARNING("not supported, ignored: %s %s" % (self.str_name, msg))

   def unsupported_yet_warn(self, msg, issue_no):
      ch.WARNING("not yet supported, ignored: issue #%d: %s %s"
                 % (issue_no, self.str_name, msg))

   def unsupported_yet_fatal(self, msg, issue_no):
      ch.FATAL("not yet supported: issue #%d: %s %s"
               % (issue_no, self.str_name, msg))


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
      raise Instruction_Ignored()


class Instruction_No_Image(Instruction):
   # This is a class for instructions that do not affect the image, i.e.,
   # no-op from the image’s perspective, but executed for their side effects,
   # e.g., changing some configuration. These instructions do not interact
   # with the build cache and can be executed when no image exists (i.e.,
   # before FROM).

   # FIXME: Only tested with instructions before the first FROM. I doubt it
   # works for instructions elsewhere.

   @property
   def miss(self):
      return True

   @property
   def status_char(self):
      return bu.cache.status_char(None)

   def checkout_for_build(self):
      pass

   def commit(self):
      pass

   def prepare(self, miss_ct):
      return miss_ct + int(self.miss)


class Arg(Instruction):

   __slots__ = ("key",
                "value")

   def __init__(self, *args):
      super().__init__(*args)
      self.commit_files.add(fs.Path("ch/metadata.json"))
      self.key = self.tree.terminal("WORD", 0)
      if (self.key in cli.build_arg):
         self.value = cli.build_arg[self.key]
         del cli.build_arg[self.key]
      else:
         self.value = self.value_default()

   @property
   def sid_input(self):
      if (self.key in im.ARGS_MAGIC):
         return (self.str_name + self.key).encode("UTF-8")
      else:
         return super().sid_input

   @property
   def str_(self):
      s = "%s=" % self.key
      if (self.value is not None):
         s += "'%s'" % self.value
      if (self.key in im.ARGS_MAGIC):
         s += " [special]"
      return s

   def prepare(self, *args):
      if (self.value is not None):
         self.value = ch.variables_sub(self.value, self.env_build)
         self.env_arg[self.key] = self.value
      return super().prepare(*args)


class I_arg_bare(Arg):

   __slots__ = ()

   def value_default(self):
      return None


class I_arg_equals(Arg):

   __slots__ = ()

   def value_default(self):
      v = self.tree.terminal("WORD", 1)
      if (v is None):
         v = unescape(self.tree.terminal("STRING_QUOTED"))
      return v


class Arg_First(Instruction_No_Image):

   __slots__ = ("key",
                "value")

   def __init__(self, *args):
      super().__init__(*args)
      self.key = self.tree.terminal("WORD", 0)
      if (self.key in cli.build_arg):
         self.value = cli.build_arg[self.key]
         del cli.build_arg[self.key]
      else:
         self.value = self.value_default()

   @property
   def str_(self):
      s = "%s=" % self.key
      if (self.value is not None):
         s += "'%s'" % self.value
      if (self.key in im.ARGS_MAGIC):
         s += " [special]"
      return s

   def prepare(self, *args):
      if (self.value is not None):
         argfrom.update({self.key: self.value})
      return super().prepare(*args)


class I_arg_first_bare(Arg_First):

   __slots__ = ()

   def value_default(self):
      return None


class I_arg_first_equals(Arg_First):

   __slots__ = ()

   def value_default(self):
      v = self.tree.terminal("WORD", 1)
      if (v is None):
         v = unescape(self.tree.terminal("STRING_QUOTED"))
      return v


class I_copy(Instruction):

   # ABANDON ALL HOPE YE WHO ENTER HERE
   #
   # Note: The Dockerfile specification for COPY is complex, messy,
   # inexplicably different from cp(1), and incomplete. We try to be
   # bug-compatible with Docker but probably are not 100%. See the FAQ.
   #
   # Because of these weird semantics, none of this abstracted into a general
   # copy function. I don’t want people calling it except from here.

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
      if (self.tree.child("copy_shell") is not None):
         args = list(self.tree.child_terminals("copy_shell", "WORD"))
      elif (self.tree.child("copy_list") is not None):
         args = list(self.tree.child_terminals("copy_list", "STRING_QUOTED"))
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
      dst = repr(self.dst) if hasattr(self, "dst") else self.dst_raw
      return "%s -> %s" % (self.srcs_raw, dst)

   def copy_src_dir(self, src, dst):
      """Copy the contents of directory src, named by COPY, either explicitly
         or with wildcards, to dst. src might be a symlink, but dst is a
         canonical path. Both must be at the top level of the COPY
         instruction; i.e., this function must not be called recursively. dst
         must exist already and be a directory. Unlike subdirectories, the
         metadata of dst will not be altered to match src."""
      def onerror(x):
         ch.FATAL("can’t scan directory: %s: %s" % (x.filename, x.strerror))
      # Use Path objects in this method because the path arithmetic was
      # getting too hard with strings.
      src = src.resolve()  # alternative to os.path.realpath()
      dst = fs.Path(dst)
      assert (src.is_dir() and not src.is_symlink())
      assert (dst.is_dir() and not dst.is_symlink())
      ch.DEBUG("copying named directory: %s -> %s" % (src, dst))
      for (dirpath, dirnames, filenames) in ch.walk(src, onerror=onerror):
         subdir = dirpath.relative_to(src)
         dst_dir = dst // subdir
         # dirnames can contain symlinks, which we handle as files, so we’ll
         # rebuild it; the walk will not descend into those “directories”.
         dirnames2 = dirnames.copy()  # shallow copy
         dirnames[:] = list()         # clear in place
         for d in dirnames2:
            src_path = dirpath // d
            dst_path = dst_dir // d
            ch.TRACE("dir: %s -> %s" % (src_path, dst_path))
            if (os.path.islink(src_path)):
               filenames.append(d)  # symlink, handle as file
               ch.TRACE("symlink to dir, will handle as file")
               continue
            else:
               dirnames.append(d)   # directory, descend into later
            # If destination exists, but isn’t a directory, remove it.
            if (os.path.exists(dst_path)):
               if (os.path.isdir(dst_path) and not os.path.islink(dst_path)):
                  ch.TRACE("dst_path exists and is a directory")
               else:
                  ch.TRACE("dst_path exists, not a directory, removing")
                  dst_path.unlink_()
            # If destination directory doesn’t exist, create it.
            if (not os.path.exists(dst_path)):
               ch.TRACE("mkdir dst_path")
               ch.ossafe(os.mkdir, "can’t mkdir: %s" % dst_path, dst_path)
            # Copy metadata, now that we know the destination exists and is a
            # directory.
            ch.ossafe(shutil.copystat,
                      "can’t copy metadata: %s -> %s" % (src_path, dst_path),
                      src_path, dst_path, follow_symlinks=False)
         for f in filenames:
            src_path = dirpath // f
            dst_path = dst_dir // f
            ch.TRACE("file or symlink via copy2: %s -> %s"
                      % (src_path, dst_path))
            if (not (os.path.isfile(src_path) or os.path.islink(src_path))):
               ch.FATAL("can’t COPY: unknown file type: %s" % src_path)
            if (os.path.exists(dst_path)):
               ch.TRACE("destination exists, removing")
               if (os.path.isdir(dst_path) and not os.path.islink(dst_path)):
                  dst_path.rmtree()
               else:
                  dst_path.unlink_()
            ch.copy2(src_path, dst_path, follow_symlinks=False)

   def copy_src_file(self, src, dst):
      """Copy file src to dst. src might be a symlink, but dst is a canonical
         path. Both must be at the top level of the COPY instruction; i.e.,
         this function must not be called recursively. dst has additional
         constraints:

           1. If dst is a directory that exists, src will be copied into that
              directory like cp(1); e.g. “COPY file_ /dir_” will produce a
              file in the imaged called. “/dir_/file_”.

           2. If dst is a regular file that exists, src will overwrite it.

           3. If dst is another type of file that exists, that’s an error.

           4. If dst does not exist, the parent of dst must be a directory
              that exists."""
      assert (src.is_file())
      assert (not dst.is_symlink())
      assert (   (dst.exists() and (dst.is_dir() or dst.is_file()))
              or (not dst.exists() and dst.parent.is_dir()))
      ch.DEBUG("copying named file: %s -> %s" % (src, dst))
      ch.copy2(src, dst, follow_symlinks=True)

   def dest_realpath(self, unpack_path, dst):
      """Return the canonicalized version of path dst within (canonical) image
         path unpack_path. We can’t use os.path.realpath() because if dst is
         an absolute symlink, we need to use the *image’s* root directory, not
         the host. Thus, we have to resolve symlinks manually."""
      dst_canon = unpack_path
      dst_parts = list(reversed(dst.parts))  # easier to operate on end of list
      iter_ct = 0
      while (len(dst_parts) > 0):
         iter_ct += 1
         if (iter_ct > 100):  # arbitrary
            ch.FATAL("can’t COPY: too many path components")
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
            target = fs.Path(os.readlink(cand))
            ch.TRACE("symlink to: %s" % target)
            assert (len(target.parts) > 0)  # POSIX says no empty symlinks
            if (target.is_absolute()):
               ch.TRACE("absolute")
               dst_canon = fs.Path(unpack_path)
            else:
               ch.TRACE("relative")
            dst_parts.extend(reversed(target.parts))
      return dst_canon

   def execute(self):
      # Locate the destination.
      unpack_canon = fs.Path(self.image.unpack_path).resolve()
      if (self.dst.startswith("/")):
         dst = fs.Path(self.dst)
      else:
         dst = self.workdir // self.dst
      ch.VERBOSE("destination, as given: %s" % dst)
      dst_canon = self.dest_realpath(unpack_canon, dst) # strips trailing slash
      ch.VERBOSE("destination, canonical: %s" % dst_canon)
      if (not os.path.commonpath([dst_canon, unpack_canon])
              .startswith(str(unpack_canon))):
         ch.FATAL("can’t COPY: destination not in image: %s" % dst_canon)
      # Create the destination directory if needed.
      if (   self.dst.endswith("/")
          or len(self.srcs) > 1
          or self.srcs[0].is_dir()):
         if (not dst_canon.exists()):
            dst_canon.mkdirs()
         elif (not dst_canon.is_dir()):  # not symlink b/c realpath()
            ch.FATAL("can’t COPY: not a directory: %s" % dst_canon)
      if (dst_canon.parent.exists()):
         if (not dst_canon.parent.is_dir()):
            ch.FATAL("can’t COPY: not a directory: %s" % dst_canon.parent)
      else:
         dst_canon.parent.mkdirs()
      # Copy each source.
      for src in self.srcs:
         if (src.is_file()):
            self.copy_src_file(src, dst_canon)
         elif (src.is_dir()):
            self.copy_src_dir(src, dst_canon)
         else:
            ch.FATAL("can’t COPY: unknown file type: %s" % src)

   def prepare(self, miss_ct):
      def stat_bytes(path, links=False):
         st = path.stat_(links)
         return (  str(path).encode("UTF-8")
                 + struct.pack("=HQQ", st.st_mode, st.st_size, st.st_mtime_ns))
      # Error checking.
      if (cli.context == "-" and self.from_ is None):
         ch.FATAL("no context because “-” given")
      if (len(self.srcs_raw) < 1):
         ch.FATAL("must specify at least one source")
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
            ch.FATAL("--from: stage %s is the current stage" % self.from_)
         if (not self.from_ in images):
            # FIXME: Would be nice to also report if a named stage is below.
            if (isinstance(self.from_, int) and self.from_ < image_ct):
               if (self.from_ < 0):
                  ch.FATAL("--from: invalid negative stage index %d"
                           % self.from_)
               else:
                  ch.FATAL("--from: stage %d does not exist yet"
                           % self.from_)
            else:
               ch.FATAL("--from: stage %s does not exist" % self.from_)
         context = images[self.from_].unpack_path
      context_canon = os.path.realpath(context)
      ch.VERBOSE("context: %s" % context)
      # Expand sources.
      self.srcs = list()
      for src in (ch.variables_sub(i, self.env_build) for i in self.srcs_raw):
         # glob can’t take Path
         matches = [fs.Path(i) for i in glob.glob("%s/%s" % (context, src))]
         if (len(matches) == 0):
            ch.FATAL("source file not found: %s" % src)
         for i in matches:
            self.srcs.append(i)
            ch.VERBOSE("source: %s" % i)
      # Expand destination.
      self.dst = ch.variables_sub(self.dst_raw, self.env_build)
      # Validate sources are within context directory. (Can’t convert to
      # canonical paths yet because we need the source path as given.)
      for src in self.srcs:
         src_canon = src.resolve()
         if (not os.path.commonpath([src_canon, context_canon])
                 .startswith(context_canon)): # no clear substitute for
                                              # commonpath in pathlib
            ch.FATAL("can’t copy from outside context: %s" % src)
      # Gather metadata for hashing.
      # FIXME: Locale issues related to sorting?
      self.src_metadata = bytearray()
      for src in self.srcs:
         self.src_metadata += stat_bytes(src, links=True)
         if (src.is_dir()):
            for (dir_, dirs, files) in ch.walk(src):
               self.src_metadata += stat_bytes(dir_)
               for f in sorted(files):
                  self.src_metadata += stat_bytes(dir_ // f)
               dirs.sort()
      # Pass on to superclass.
      return super().prepare(miss_ct)


class I_directive(Instruction_Supported_Never):

   __slots__ = ()

   @property
   def str_name(self):
      return "#%s" % self.tree.terminal("DIRECTIVE_NAME")

   def prepare(self, *args):
      ch.WARNING("not supported, ignored: parser directives")
      raise Instruction_Ignored()


class Env(Instruction):

   __slots__ = ("key",
                "value")

   def __init__(self, *args):
      super().__init__(*args)
      self.commit_files |= {fs.Path("ch/environment"),
                            fs.Path("ch/metadata.json")}

   @property
   def str_(self):
      return "%s='%s'" % (self.key, self.value)

   def execute(self):
      with (self.image.unpack_path // "/ch/environment").open_("wt") \
           as fp:
         for (k, v) in self.env_env.items():
            print("%s=%s" % (k, v), file=fp)

   def prepare(self, *args):
      self.value = ch.variables_sub(unescape(self.value), self.env_build)
      self.env_env[self.key] = self.value
      return super().prepare(*args)


class I_env_equals(Env):

   __slots__ = ()

   def __init__(self, *args):
      super().__init__(*args)
      self.key = self.tree.terminal("WORD", 0)
      self.value = self.tree.terminal("WORD", 1)
      if (self.value is None):
         self.value = self.tree.terminal("STRING_QUOTED")


class I_env_space(Env):

   __slots__ = ()

   def __init__(self, *args):
      super().__init__(*args)
      self.key = self.tree.terminal("WORD")
      self.value = self.tree.terminals_cat("LINE_CHUNK")


class Label(Instruction):

   __slots__ = ("key",
                "value")

   def __init__(self, *args):
      super().__init__(*args)
      self.commit_files |= {ch.Path("ch/metadata.json")}

   @property
   def str_(self):
      return "%s='%s'" % (self.key, self.value)

   def prepare(self, *args):
      self.value = ch.variables_sub(unescape(self.value), self.env_build)
      self.image.metadata["labels"][self.key] = self.value
      return super().prepare(*args)


class I_label_equals(Label):

   __slots__ = ()

   def __init__(self, *args):
      super().__init__(*args)
      self.key = self.tree.terminal("WORD", 0)
      self.value = self.tree.terminal("WORD", 1)
      if (self.value is None):
         self.value = self.tree.terminal("STRING_QUOTED")


class I_label_space(Label):

   __slots__ = ()

   def __init__(self, *args):
      super().__init__(*args)
      self.key = self.tree.terminal("WORD")
      self.value = self.tree.terminals_cat("LINE_CHUNK")


class I_from_(Instruction):

   __slots__ = ("alias",
                "base_alias",
                "base_image",
                "base_text")

   def __init__(self, *args):
      super().__init__(*args)
      argfrom.update(self.options.pop("arg", {}))

   # Not meaningful for FROM.
   sid_input = None

   @property
   def str_(self):
      if (hasattr(self, "base_alias")):
         base_text = str(self.base_alias)
      elif (hasattr(self, "base_image")):
         base_text = str(self.base_image.ref)
      else:
         # Initialization failed, but we want to print *something*.
         base_text = self.base_text
      return base_text + ((" AS " + self.alias) if self.alias else "")

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
      self.base_text = self.tree.child_terminals_cat("image_ref", "IMAGE_REF")
      self.alias = self.tree.child_terminal("from_alias", "IR_PATH_COMPONENT")
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
         tag = "%s_stage%d" % (cli.tag, self.image_i)
      if self.base_text in images:
         # Is alias; store base_text as the “alias used” to target a previous
         # stage as the base.
         self.base_alias = self.base_text
         self.base_text = str(images[self.base_text].ref)
      self.base_image = im.Image(im.Reference(self.base_text, argfrom))
      self.image = im.Image(im.Reference(tag))
      images[self.image_i] = self.image
      if (self.image_alias is not None):
         images[self.image_alias] = self.image
      ch.VERBOSE("image path: %s" % self.image.unpack_path)
      # More error checking.
      if (str(self.image.ref) == str(self.base_image.ref)):
         ch.FATAL("output image ref same as FROM: %s" % self.base_image.ref)
      # Close previous stage if needed. In particular, we need the previous
      # stage’s image directory to exist because (a) we need to read its
      # metadata and (b) in case there’s a COPY later. Cache disabled will
      # already have the image directory and there is no notion of branch
      # “ready”, so do nothing in that case.
      if (self.image_i > 0 and not isinstance(bu.cache, bu.Disabled_Cache)):
         if (miss_ct == 0):
            # No previous miss already checked out the image. This will still
            # be fast most of the time since the correct branch is likely
            # checked out already.
            self.parent.checkout()
         self.parent.ready()
      # At this point any meaningful parent of FROM, e.g., previous stage, has
      # been closed; thus, act as own parent.
      self.parent = self
      # Pull base image if needed. This tells us hit/miss.
      (self.sid, self.git_hash) = bu.cache.find_image(self.base_image)
      unpack_no_git = (    self.base_image.unpack_exist_p
                       and not self.base_image.unpack_cache_linked)
      # Announce (before we start pulling).
      self.announce_maybe()
      # FIXME: shouldn’t know or care whether build cache is enabled here.
      if (self.miss):
         if (unpack_no_git):
            # Use case is mostly images built by old ch-image still in storage.
            if (not isinstance(bu.cache, bu.Disabled_Cache)):
               ch.WARNING("base image only exists non-cached; adding to cache")
            (self.sid, self.git_hash) = bu.cache.adopt(self.base_image)
         else:
            (self.sid, self.git_hash) = bu.cache.pull_lazy(self.base_image,
                                                           self.base_image.ref)
      elif (unpack_no_git):
         ch.WARNING("base image also exists non-cached; using cache")
      # Load metadata
      self.image.metadata_load(self.base_image)
      self.env_arg.update(argfrom)  # from pre-FROM ARG

      # Done.
      return int(self.miss)  # will still miss in disabled mode

   def execute(self):
      # Everything happens in prepare().
      pass


class Run(Instruction):

   __slots__ = ("cmd")

   @property
   def str_name(self):
      # Can’t get this from the forcer object because it might not have been
      # initialized yet.
      if (cli.force == "none"):
         tag = ".N"
      elif (cli.force == "fakeroot"):
         # FIXME: This causes spurious misses because it adds the force tag to
         # *all* RUN instructions, not just those that actually were modified
         # (i.e, any RUN instruction will miss the equivalent RUN without
         # --force=fakeroot). But we don’t know know if an instruction needs
         # modifications until the result is checked out, which happens after
         # we check the cache. See issue #1339.
         tag = ".F"
      elif (cli.force == "seccomp"):
         tag = ".S"
      else:
         assert False, "unreachable code reached"
      return super().str_name + tag

   def execute(self):
      rootfs = self.image.unpack_path
      cmd = forcer.run_modified(self.cmd, self.env_build)
      exit_code = ch.ch_run_modify(rootfs, cmd, self.env_build, self.workdir,
                                   cli.bind, forcer.ch_run_args, fail_ok=True)
      if (exit_code != 0):
         ch.FATAL("build failed: RUN command exited with %d" % exit_code)


class I_run_exec(Run):

   __slots__ = ()

   @property
   def str_(self):
      return json.dumps(self.cmd)  # double quotes, shlex.quote is less verbose

   def prepare(self, *args):
      self.cmd = [    ch.variables_sub(unescape(i), self.env_build)
                  for i in self.tree.terminals("STRING_QUOTED")]
      return super().prepare(*args)


class I_run_shell(Run):

   # Note re. line continuations and whitespace: Whitespace before the
   # backslash is passed verbatim to the shell, while the newline and any
   # whitespace between the newline and baskslash are deleted.

   __slots__ = ("_str_")

   @property
   def str_(self):
      return self._str_  # can’t replace abstract property with attribute

   def prepare(self, *args):
      cmd = self.tree.terminals_cat("LINE_CHUNK")
      self.cmd = self.shell + [cmd]
      self._str_ = cmd
      return super().prepare(*args)


class I_shell(Instruction):

   def __init__(self, *args):
      super().__init__(*args)
      self.commit_files.add(fs.Path("ch/metadata.json"))

   @property
   def str_(self):
      return str(self.shell)

   def prepare(self, *args):
      self.shell = [    ch.variables_sub(unescape(i), self.env_build)
                    for i in self.tree.terminals("STRING_QUOTED")]
      return super().prepare(*args)


class I_workdir(Instruction):

   __slots__ = ("path")

   @property
   def str_(self):
      return str(self.path)

   def execute(self):
      (self.image.unpack_path // self.workdir).mkdirs()

   def prepare(self, *args):
      self.path = fs.Path(ch.variables_sub(
         self.tree.terminals_cat("LINE_CHUNK"), self.env_build))
      self.chdir(self.path)
      return super().prepare(*args)


class I_uns_forever(Instruction_Supported_Never):

   __slots__ = ("name")

   def __init__(self, *args):
      super().__init__(*args)
      self.name = self.tree.terminal("UNS_FOREVER")

   @property
   def str_name(self):
      return self.name


class I_uns_yet(Instruction_Unsupported):

   __slots__ = ("issue_no",
                "name")

   def __init__(self, *args):
      super().__init__(*args)
      self.name = self.tree.terminal("UNS_YET")
      self.issue_no = { "ADD":         782,
                        "CMD":         780,
                        "ENTRYPOINT":  780,
                        "ONBUILD":     788 }[self.name]

   @property
   def str_name(self):
      return self.name

   def prepare(self, *args):
      self.unsupported_yet_warn("instruction", self.issue_no)
      raise Instruction_Ignored()


## Supporting classes ##

class Environment:
   """The state we are in: environment variables, working directory, etc. Most
      of this is just passed through from the image metadata."""

   # FIXME:
   # - problem:
   #   1. COPY (at least) needs a valid build environment to figure out if it’s
   #      a hit or miss, which happens in prepare()
   #   2. no files from the image are available in prepare(), so we can’t read
   #      image metadata then
   #      - could get it from Git if needed, but that seems complicated
   # - valid during prepare() and execute() but not __init__()
   #   - in particular, don’t ch.variables_sub() in __init__()
   # - instructions that update it need to change the env object in prepare()
   #   - WORKDIR SHELL ARG ENV
   #   - FROM
   #     - global images and image_i makes this harder because we need to read
   #       the metadata of image_i - 1
   #       - solution: remove those two globals? instructions grow image and
   #         image_i attributes?


## Supporting functions ###

def unescape(sl):
   # FIXME: This is also ugly and should go in the grammar.
   #
   # The Dockerfile spec does not precisely define string escaping, but I’m
   # guessing it’s the Go rules. You will note that we are using Python rules.
   # This is wrong but close enough for now (see also gripe in previous
   # paragraph).
   if (    not sl.startswith('"')                          # no start quote
       and (not sl.endswith('"') or sl.endswith('\\"'))):  # no end quote
      sl = '"%s"' % sl
   assert (len(sl) >= 2 and sl[0] == '"' and sl[-1] == '"' and sl[-2:] != '\\"')
   return ast.literal_eval(sl)


#  LocalWords:  earley topdown iter lineno sid keypair dst srcs pathlib
