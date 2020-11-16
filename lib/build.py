# Implementation of "ch-grow build".

import abc
import ast
import glob
import inspect
import os
import os.path
import pathlib
import re
import shutil
import sys

import charliecloud as ch
import fakeroot


## Globals ##

# Namespace from command line arguments. FIXME: be more tidy about this ...
cli = None

# Environment object.
env = None

# Images that we are building. Each stage gets its own image. In this
# dictionary, an image appears exactly once or twice. All images appear with
# an int key counting stages up from zero. Images with a name (e.g., "FROM ...
# AS foo") have a second string key of the name.
images = dict()
# Current stage. Incremented by FROM instructions; the first will set it to 0.
image_i = -1
image_alias = None
# Number of stages.
image_ct = None


## Imports not in standard library ##

# See charliecloud.py for the messy import of this.
lark = ch.lark


## Constants ##

ARG_DEFAULTS = { "HTTP_PROXY": os.environ.get("HTTP_PROXY"),
                 "HTTPS_PROXY": os.environ.get("HTTPS_PROXY"),
                 "FTP_PROXY": os.environ.get("FTP_PROXY"),
                 "NO_PROXY": os.environ.get("NO_PROXY"),
                 "http_proxy": os.environ.get("http_proxy"),
                 "https_proxy": os.environ.get("https_proxy"),
                 "ftp_proxy": os.environ.get("ftp_proxy"),
                 "no_proxy": os.environ.get("no_proxy"),
                 "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                 # GNU tar, when it thinks it's running as root, tries to
                 # chown(2) and chgrp(2) files to whatever's in the tarball.
                 "TAR_OPTIONS": "--no-same-owner" }

ENV_DEFAULTS = { }


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
      m = re.search(r"(([^/]+)/)?Dockerfile(\.(.+))?$",
                    os.path.abspath(cli.file))
      if (m is not None):
         if m.group(4):    # extension
            cli.tag = m.group(4)
         elif m.group(2):  # containing directory
            cli.tag = m.group(2)

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
   if (cli.build_arg is None):
      cli.build_arg = list()
   cli.build_arg = dict( build_arg_get(i) for i in cli.build_arg )

   # Finish CLI initialization.
   ch.DEBUG(cli)
   ch.dependencies_check()

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

   # Set up build environment.
   global env
   env = Environment()

   # Read input file.
   if (cli.file == "-"):
      text = ch.ossafe(sys.stdin.read, "can't read stdin")
   else:
      fp = ch.open_(cli.file, "rt")
      text = ch.ossafe(fp.read, "can't read: %s" % cli.file)
      fp.close()

   # Parse it.
   parser = lark.Lark("?start: dockerfile\n" + ch.GRAMMAR,
                      parser="earley", propagate_positions=True)
   # Avoid Lark issue #237: lark.exceptions.UnexpectedEOF if the file does not
   # end in newline.
   text += "\n"
   try:
      tree = parser.parse(text)
   except lark.exceptions.UnexpectedInput as x:
      ch.DEBUG(x)  # noise about what was expected in the grammar
      ch.FATAL("can't parse: %s:%d,%d\n\n%s" % (cli.file, x.line, x.column, x.get_context(text, 39)))
   ch.DEBUG(tree.pretty())

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

   # Check that all build arguments were consumed.
   if (len(cli.build_arg) != 0):
      ch.FATAL("--build-arg: not consumed: " + " ".join(cli.build_arg.keys()))

   # Print summary & we're done.
   if (ml.instruction_ct == 0):
      ch.FATAL("no instructions found: %s" % cli.file)
   assert (image_i + 1 == image_ct)  # should have errored already if not
   ch.INFO("grown in %d instructions: %s"
           % (ml.instruction_ct, images[image_i]))

class Main_Loop(lark.Visitor):

   def __init__(self, *args, **kwargs):
      self.instruction_ct = 0
      super().__init__(*args, **kwargs)

   def __default__(self, tree):
      class_ = "I_" + tree.data
      if (class_ in globals()):
         inst = globals()[class_](tree)
         inst.announce()
         if (self.instruction_ct == 0):
            if (   isinstance(inst, I_directive)
                or isinstance(inst, I_from_)):
               pass
            elif (isinstance(inst, Arg)):
               ch.WARNING("ARG before FROM not yet supported; see issue #779")
            else:
               ch.FATAL("first instruction must be ARG or FROM")
         inst.execute()
         self.instruction_ct += inst.execute_increment


## Instruction classes ##

class Instruction(abc.ABC):

   execute_increment = 1

   def __init__(self, tree):
      self.lineno = tree.meta.line
      self.options = {}
      for st in ch.tree_children(tree, "option"):
         k = ch.tree_terminal(st, "OPTION_KEY")
         v = ch.tree_terminal(st, "OPTION_VALUE")
         if (k in self.options):
            ch.FATAL("%3d %s: repeated option --%s"
                     % (self.lineno, self.str_name(), k))
         self.options[k] = v
      # Save original options string because instructions pop() from the dict
      # to process them.
      self.options_str = " ".join("--%s=%s" % (k,v)
                                  for (k,v) in self.options.items())
      self.tree = tree

   def __str__(self):
      options = self.options_str
      if (options != ""):
         options = " " + options
      return ("%3s %s%s %s"
              % (self.lineno, self.str_name(), options, self.str_()))

   def announce(self):
      ch.INFO(self)

   def execute(self):
      if (not cli.dry_run):
         self.execute_()

   @abc.abstractmethod
   def execute_(self):
      ...

   def options_assert_empty(self):
      try:
         k = next(iter(self.options.keys()))
         ch.FATAL("%s: invalid option --%s" % (self.str_name(), k))
      except StopIteration:
         pass

   @abc.abstractmethod
   def str_(self):
      ...

   def str_name(self):
      return self.__class__.__name__.split("_")[1].upper()

   def unsupported_forever_warn(self, msg):
      ch.WARNING("not supported, ignored: %s %s" % (self.str_name(), msg))

   def unsupported_yet_warn(self, msg, issue_no):
      ch.WARNING("not yet supported, ignored: issue #%d: %s %s"
                 % (issue_no, self.str_name(), msg))

   def unsupported_yet_fatal(self, msg, issue_no):
      ch.FATAL("not yet supported: issue #%d: %s %s"
               % (issue_no, self.str_name(), msg))


class Instruction_Supported_Never(Instruction):

   execute_increment = 0

   def announce(self):
      self.unsupported_forever_warn("instruction")

   def str_(self):
      return "(unsupported)"

   def execute_(self):
      pass


class Arg(Instruction):

   def __init__(self, *args):
      super().__init__(*args)
      self.key = ch.tree_terminal(self.tree, "WORD", 0)
      if (self.key in cli.build_arg):
         self.value = cli.build_arg[self.key]
         del cli.build_arg[self.key]
      else:
         self.value = self.value_default()
      if (self.value is not None):
         self.value = variables_sub(self.value, env.env_build)

   def str_(self):
      if (self.value is None):
         return self.key
      else:
         return "%s='%s'" % (self.key, self.value)

   def execute_(self):
      if (self.value is not None):
         env.arg[self.key] = self.value


class I_arg_bare(Arg):

   def __init__(self, *args):
      super().__init__(*args)

   def value_default(self):
      return None


class I_arg_equals(Arg):

   def __init__(self, *args):
      super().__init__(*args)

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

   def __init__(self, *args):
      super().__init__(*args)
      self.from_ = self.options.pop("from", None)
      if (self.from_ is not None):
         try:
            self.from_ = int(self.from_)
         except ValueError:
            pass
      if (ch.tree_child(self.tree, "copy_shell") is not None):
         paths = [variables_sub(i, env.env_build)
                  for i in ch.tree_child_terminals(self.tree, "copy_shell",
                                                   "WORD")]
         self.srcs = paths[:-1]
         self.dst = paths[-1]
      else:
         assert (ch.tree_child(self.tree, "copy_list") is not None)
         self.unsupported_yet_fatal("list form", 784)

   def str_(self):
      return "%s -> %s" % (self.srcs, repr(self.dst))

   def copy_src_dir(self, src, dst):
      """Copy the contents of directory src, named by COPY, either explicitly
         or with wildcards, to dst. src might be a symlink, but dst is a
         canonical path. Both must be at the top level of the COPY
         instruction; i.e., this function must not be called recursively. dst
         must exist already and be a directory. Unlike subdirectories, the
         metadata of dst will not be altered to match src."""
      def onerror(x):
         ch.FATAL("error scanning directory: %s: %s" % (x.filename, x.strerror))
      # Use Path objects in this method because the path arithmetic was
      # getting too hard with strings.
      src = pathlib.Path(os.path.realpath(src))
      dst = pathlib.Path(dst)
      assert (os.path.isdir(src) and not os.path.islink(src))
      assert (os.path.isdir(dst) and not os.path.islink(dst))
      ch.DEBUG("copying named directory: %s -> %s" % (src, dst))
      for (dirpath, dirnames, filenames) in os.walk(src, onerror=onerror):
         dirpath = pathlib.Path(dirpath)
         subdir = dirpath.relative_to(src)
         dst_dir = dst / subdir
         # dirnames can contain symlinks, which we handle as files, so we'll
         # rebuild it; the walk will not descend into those "directories".
         dirnames2 = dirnames.copy()  # shallow copy
         dirnames[:] = list()         # clear in place
         for d in dirnames2:
            d = pathlib.Path(d)
            src_path = dirpath / d
            dst_path = dst_dir / d
            ch.DEBUG("dir: %s -> %s" % (src_path, dst_path), v=2)
            if (os.path.islink(src_path)):
               filenames.append(d)  # symlink, handle as file
               ch.DEBUG("symlink to dir, will handle as file")
               continue
            else:
               dirnames.append(d)   # directory, descend into later
            # If destination exists, but isn't a directory, remove it.
            if (os.path.exists(dst_path)):
               if (os.path.isdir(dst_path) and not os.path.islink(dst_path)):
                  ch.DEBUG("dst_path exists and is a directory", v=2)
               else:
                  ch.DEBUG("dst_path exists, not a directory, removing", v=2)
                  ch.unlink(dst_path)
            # If destination directory doesn't exist, create it.
            if (not os.path.exists(dst_path)):
               ch.DEBUG("mkdir dst_path", v=2)
               ch.ossafe(os.mkdir, "can't mkdir: %s" % dst_path, dst_path)
            # Copy metadata, now that we know the destination exists and is a
            # directory.
            ch.ossafe(shutil.copystat,
                      "can't copy metadata: %s -> %s" % (src_path, dst_path),
                      src_path, dst_path, follow_symlinks=False)
         for f in filenames:
            f = pathlib.Path(f)
            src_path = dirpath / f
            dst_path = dst_dir / f
            ch.DEBUG("file or symlink via copy2: %s -> %s"
                     % (src_path, dst_path), v=2)
            if (not (os.path.isfile(src_path) or os.path.islink(src_path))):
               ch.FATAL("can't COPY: unknown file type: %s" % src_path)
            if (os.path.exists(dst_path)):
               ch.DEBUG("destination exists, removing")
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

   def execute_(self):
      # Complain about unsupported stuff.
      if (self.options.pop("chown", False)):
         self.unsupported_forever_warn("--chown")
      # Any remaining options are invalid.
      self.options_assert_empty()
      # Find the context directory.
      if (self.from_ is None):
         context = cli.context
      else:
         if (self.from_ == image_i or self.from_ == image_alias):
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
      ch.DEBUG("context: %s" % context)
      # Expand source wildcards.
      srcs = list()
      for src in self.srcs:
         for i in glob.glob(context + "/" + src):
            srcs.append(i)
            ch.DEBUG("found source: %s" % i)
      if (len(srcs) == 0):
         ch.FATAL("can't COPY: no sources found")
      # Validate sources are within context directory. (Can't convert to
      # canonical paths yet because we need the source path as given.)
      for src in srcs:
         src_canon = os.path.realpath(src)
         if (not os.path.commonpath([src_canon, context_canon])
                 .startswith(context_canon)):
            ch.FATAL("can't COPY from outside context: %s" % src)
      # Locate the destination.
      dst = images[image_i].unpack_path + "/"
      if (not self.dst.startswith("/")):
         dst += env.workdir + "/"
      dst += self.dst
      dst_canon = os.path.realpath(dst)  # strips trailing slash if any
      unpack_canon = os.path.realpath(images[image_i].unpack_path)
      if (not os.path.commonpath([dst_canon, unpack_canon])
              .startswith(unpack_canon)):
         ch.FATAL("can't COPY: destination not in image: %s" % dst_canon)
      ch.DEBUG("destination: %s" % dst_canon)
      # Create the destination directory if needed.
      if (dst.endswith("/") or len(srcs) > 1 or os.path.isdir(srcs[0])):
         if (not os.path.exists(dst_canon)):
            ch.mkdirs(dst_canon)
         elif (not os.path.isdir(dst_canon)):  # not symlink b/c realpath()
            ch.FATAL("can't COPY: not a directory: %s" % dst_canon)
      # Copy each source.
      for src in srcs:
         if (os.path.isfile(src)):
            self.copy_src_file(src, dst_canon)
         elif (os.path.isdir(src)):
            self.copy_src_dir(src, dst_canon)
         else:
            ch.FATAL("can't COPY: unknown file type: %s" % src)


class I_directive(Instruction_Supported_Never):

   def __init__(self, *args):
      super().__init__(*args)

   def announce(self):
      ch.WARNING("not supported, ignored: parser directives")


class Env(Instruction):

   def str_(self):
      return "%s='%s'" % (self.key, self.value)

   def execute_(self):
      env.env[self.key] = self.value
      with ch.open_(images[image_i].unpack_path + "/ch/environment", "wt") \
           as fp:
         for (k, v) in env.env.items():
            print("%s=%s" % (k, v), file=fp)


class I_env_equals(Env):

   def __init__(self, *args):
      super().__init__(*args)
      self.key = ch.tree_terminal(self.tree, "WORD", 0)
      self.value = ch.tree_terminal(self.tree, "WORD", 1)
      if (self.value is None):
         self.value = unescape(ch.tree_terminal(self.tree, "STRING_QUOTED"))
      self.value = variables_sub(self.value, env.env_build)


class I_env_space(Env):

   def __init__(self, *args):
      super().__init__(*args)
      self.key = ch.tree_terminal(self.tree, "WORD")
      value = ch.tree_terminal(self.tree, "LINE")
      if (not value.startswith('"')):
         value = '"' + value + '"'
      self.value = unescape(value)
      self.value = variables_sub(self.value, env.env_build)


class I_from_(Instruction):

   def __init__(self, *args):
      super().__init__(*args)
      self.base_ref = ch.Image_Ref(ch.tree_child(self.tree, "image_ref"))
      self.alias = ch.tree_child_terminal(self.tree, "from_alias",
                                          "IR_PATH_COMPONENT")

   def execute_(self):
      # Complain about unsupported stuff.
      if (self.options.pop("platform", False)):
         self.unsupported_yet_fatal("--platform", 778)
      # Any remaining options are invalid.
      self.options_assert_empty()
      # Update image globals.
      global image_i
      image_i += 1
      global image_alias
      image_alias = self.alias
      if (image_i == image_ct - 1):
         # Last image; use tag unchanged.
         tag = cli.tag
      elif (image_i > image_ct - 1):
         # Too many images!
         ch.FATAL("expected %d stages but found at least %d"
                  % (image_ct, image_i + 1))
      else:
         # Not last image; append stage index to tag.
         tag = "%s/_stage%d" % (cli.tag, image_i)
      image = ch.Image(ch.Image_Ref(tag), cli.storage + "/dlcache",
                       cli.storage + "/img")
      images[image_i] = image
      if (self.alias is not None):
         images[self.alias] = image
      ch.DEBUG("image path: %s" % image.unpack_path)
      # Other error checking.
      if (str(image.ref) == str(self.base_ref)):
         ch.FATAL("output image ref same as FROM: %s" % self.base_ref)
      # Initialize image.
      self.base_image = ch.Image(self.base_ref, image.download_cache,
                                 image.unpack_dir)
      if (not os.path.isdir(self.base_image.unpack_path)):
         ch.DEBUG("image not found, pulling: %s" % self.base_image.unpack_path)
         self.base_image.pull_to_unpacked(fixup=True)
      image.copy_unpacked(self.base_image)
      env.reset()
      # Inject fakeroot preparatory stuff if needed.
      if (not cli.no_fakeroot):
         fakeroot.inject_first(image.unpack_path, env.env_build)

   def str_(self):
      alias = "AS %s" % self.alias if self.alias else ""
      return "%s %s" % (self.base_ref, alias)


class Run(Instruction):

   def cmd_set(self, args):
      # This can be called if RUN is erroneously placed before FROM; in this
      # case there is no image yet, so don't inject.
      if (cli.no_fakeroot or image_i not in images):
         self.cmd = args
      else:
         self.cmd = fakeroot.inject_each(images[image_i].unpack_path, args)

   def execute_(self):
      rootfs = images[image_i].unpack_path
      ch.ch_run_modify(rootfs, self.cmd, env.env_build, env.workdir)

   def str_(self):
      return str(self.cmd)


class I_run_exec(Run):

   def __init__(self, *args):
      super().__init__(*args)
      self.cmd_set([    variables_sub(unescape(i), env.env_build)
                    for i in ch.tree_terminals(self.tree, "STRING_QUOTED")])


class I_run_shell(Run):

   def __init__(self, *args):
      super().__init__(*args)
      # FIXME: Can't figure out how to remove continuations at parse time.
      cmd = ch.tree_terminal(self.tree, "LINE").replace("\\\n", "")
      self.cmd_set(["/bin/sh", "-c", cmd])


class I_workdir(Instruction):

   def __init__(self, *args):
      super().__init__(*args)
      self.path = variables_sub(ch.tree_terminal(self.tree, "LINE"),
                                env.env_build)

   def str_(self):
      return self.path

   def execute_(self):
      env.chdir(self.path)
      ch.mkdirs(images[image_i].unpack_path + env.workdir)


class I_uns_forever(Instruction_Supported_Never):

   def __init__(self, *args):
      super().__init__(*args)
      self.name = ch.tree_terminal(self.tree, "UNS_FOREVER")

   def str_name(self):
      return self.name


class I_uns_yet(Instruction):

   execute_increment = 0

   def __init__(self, *args):
      super().__init__(*args)
      self.name = ch.tree_terminal(self.tree, "UNS_YET")
      self.issue_no = { "ADD":         782,
                        "CMD":         780,
                        "ENTRYPOINT":  780,
                        "LABEL":       781,
                        "ONBUILD":     788,
                        "SHELL":       789 }[self.name]

   def announce(self):
      self.unsupported_yet_warn("instruction", self.issue_no)

   def str_(self):
      return "(unsupported)"

   def str_name(self):
      return self.name

   def execute_(self):
      pass


## Supporting classes ##

class Environment:
   "The state we are in: environment variables, working directory, etc."

   def __init__(self):
      self.reset()

   @property
   def env_build(self):
      return { **self.arg, **self.env }

   def chdir(self, path):
      if (path.startswith("/")):
         self.workdir = path
      else:
         self.workdir += "/" + path

   def reset(self):
      self.workdir = "/"
      self.arg = { k: v for (k, v) in ARG_DEFAULTS.items() if v is not None }
      self.env = { k: v for (k, v) in ENV_DEFAULTS.items() if v is not None }


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
   if (not (sl.startswith('"') and sl.endswith('"'))):
      ch.FATAL("string literal not quoted")
   return ast.literal_eval(sl)
