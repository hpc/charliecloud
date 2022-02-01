import enum
import os
import re
import tempfile

import charliecloud as ch


## Constants ##

# Required versions.
DOT_MIN = (2, 40, 1)
GIT_MIN = (2, 34, 1)
GIT2DOT_MIN = (0, 8, 3)


## Globals ##

# The active build cache.
cache = None


## Functions ##

def have_deps():
   """Return True if dependencies for the build cache are present, False
      otherwise. Note this does not include the --dot debugging option; that
      checks its own dependencies when invoked."""
   # As of 2.34.1, we get: "git version 2.34.1\n".
   if (not ch.version_check(["git", "--version"], GIT_MIN, required=False)):
      return False
   return True


def init(cli):
   # At this point --bucache is what the user wanted, either directly or via
   # --no-cache. If it's None, chose the right default; otherwise, try what
   # the user asked for and fail if we can't do it.
   if (cli.bucache != ch.Build_Mode.DISABLED):
      ok = have_deps()
      if (cli.bucache is None):
         cli.bucache = ch.Build_Mode.ENABLED if ok else ch.Build_Mode.DISABLED
         ch.VERBOSE("using default build cache mode")
      if (cli.bucache != ch.Build_Mode.DISABLED and not ok):
         ch.FATAL("no Git or insufficient Git for build cache mode: %s"
                  % cli.bucache.value)
   ch.VERBOSE("build cache mode: %s" % cli.bucache.value)
   # Set cache appropriately. We could also do this with a factory method, but
   # that seems overkill.
   global cache
   if (cli.bucache == ch.Build_Mode.ENABLED):
      cache = Enabled_Cache()
   elif (cli.bucache == ch.Build_Mode.REBUILD):
      ...
      #cache = Rebuild_Cache()
   elif (cli.bucache == ch.Build_Mode.DISABLED):
      ...
      #cache = Disabled_Cache()
   else:
      assert False, "unreachable"


## Supporting classes ##

class State_ID:

   __slots__ = ('id_')

   def __init__(self, id_):
      """The argument is stringified; then this string must consist of 32 hex
         digits, possibly interspersed with other characters. Any following
         characters are ignored.

         Note this means you *can* pass another State_ID object, but the copy
         currently happens by stringifying then un-stringifying."""
      id_ = re.sub(r"[^0-9A-Fa-f]", "", str(id_))[:32]
      if (len(id_) < 32):
         ch.FATAL("state ID too short: %s" % id_)
      try:
         self.id_ = bytes.fromhex(id_)
      except ValueError:
         ch.FATAL("state ID: malformed hex: %s" % id_);

   def __eq__(self, other):
      return self.id_ == other.id_

   def __hash__(self):
      return hash(self.id_)

   def __str__(self):
      s = self.id_.hex().upper()
      return ":".join((s[0:4], s[4:8], s[8:16], s[16:24], s[24:32]))


## Main classes ##

class Enabled_Cache:

   root_id = State_ID("4A6F:73C3:A9204361:7061626C:616E6361")

   __slots__ = ("bootstrap_ct")

   def __init__(self):
      self.bootstrap_ct = 0
      if (not os.path.isdir(self.root)):
         ch.mkdir(self.root)
      ls = ch.listdir(self.root)
      if (len(ls) == 0):
         self.bootstrap()  # empty; initialize a new cache
      elif (not {"HEAD", "objects", "refs"} <= ls):
         # Non-empty but not an existing cache.
         # See: https://git-scm.com/docs/gitrepository-layout
         ch.FATAL("storage broken: not a build cache: %s" % self.root)

   @property
   def root(self):
      return ch.storage.build_cache

   def bootstrap(self):
      ch.INFO("initializing empty build cache")
      self.bootstrap_ct += 1
      # Initialize bare repo
      ch.cmd_quiet(["git", "init", "--bare", "-b", "root", self.root])
      # Create empty root commit. There is probably a way to do this directly
      # in the bare repo, but brief searching makes it seem pretty hairy.
      try:
         with tempfile.TemporaryDirectory(prefix="weirdal.") as td:
            ch.cmd_quiet(["git", "clone", "-q", self.root, td])
            cwd = ch.chdir(td)
            ch.cmd_quiet(["git", "checkout", "-q", "-b", "root"])
            ch.cmd_quiet(["git", "commit", "--allow-empty", "-m", self.root_id])
            ch.cmd_quiet(["git", "push", "-q", "origin", "root"])
            ch.chdir(cwd)
      except OSError as x:
         FATAL("can't create or delete temporary directory: %s: %s"
               % (x.filename, x.strerror))

   def garbageinate(self):
      ch.INFO("collecting cache garbage")
      ch.cmd_quiet(["git", "gc", "--prune=now"], cwd=self.root)

   def reset(self):
      if (self.bootstrap_ct >= 1):
         ch.WARNING("not resetting brand-new cache")
      else:
         ch.INFO("deleting build cache")
         ch.rmtree(self.root)
         ch.mkdir(self.root)
         self.bootstrap()

   def summary_print(self):
      cwd = ch.chdir(self.root)
      # state IDs
      msgs = ch.cmd_stdout(["git", "log",
                            "--all", "--reflog", "--format=format:%s"]).stdout
      states = list()
      for msg in msgs.splitlines():
         states.append(State_ID(msg))
      # branches (FIXME: how to count unnamed branch tips?)
      image_ct = ch.cmd_stdout(["git", "branch"]).stdout.count("\n")
      # file count and size on disk
      (file_ct, byte_ct) = ch.du(self.root)
      commit_ct = int(ch.cmd_stdout(["git", "rev-list",
                                     "--all", "--reflog", "--count"]).stdout)
      (file_ct, file_suffix) = ch.si_decimal(file_ct)
      (byte_ct, byte_suffix) = ch.si_binary_bytes(byte_ct)
      # print it
      print("named images:   %4d" % image_ct)
      print("states:         %4d" % len(states))
      print("unique states:  %4d" % len(set(states)))
      print("commits:        %4d" % commit_ct)
      print("files:          %4d %s" % (file_ct, file_suffix))
      print("disk used:      %4d %s" % (byte_ct, byte_suffix))

   def tree_print(self):
      # Note the percent codes are interpreted by Git.
      # See: https://git-scm.com/docs/git-log#_pretty_formats
      # FIXME: the git note, %N, has a newline and I can't get rid of it.
      if (ch.verbose == 0):
         fmt = "%C(auto)%d%C(blue)% N%Creset"
      else:
         fmt = "%C(auto)%d%C(yellow)% h%Creset%C(blue)% N%Creset%<(11,trunc)% s%n"
      ch.cmd_base(["git", "log", "--graph", "--all", "--reflog",
                   "--format=%s" % fmt], cwd=self.root)
      print()

   def tree_dot(self):
      ch.version_check(["git2dot.py", "--version"], GIT2DOT_MIN)
      ch.version_check(["dot", "-V"], DOT_MIN)
      ch.INFO("writing ./build-cache.gv")
      ch.cmd_quiet(["git2dot.py", "-l", "[%h] %s|%N", "-w", "20",
                    "%s/build-cache.gv" % os.getcwd()], cwd=self.root)
      ch.INFO("writing ./build-cache.pdf")
      ch.cmd_quiet(["dot", "-Tpdf", "-obuild-cache.pdf", "build-cache.gv"])
