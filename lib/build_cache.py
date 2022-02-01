import enum
import os
import re
import tempfile

import charliecloud as ch


## Constants ##

# Required versions.
GIT_MIN = ( 2, 34, 1)
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
   cp = ch.cmd_stdout(["git", "--version"], fail_ok=True)
   if (cp.returncode != 0):
      ch.VERBOSE("can't obtain Git version, assuming not present")
      return False
   m = re.search(r".*(\d+)\.(\d+)\.(\d+)\s+", cp.stdout)
   if (m is None):
      ch.WARNING("can't parse Git version, assuming no Git: %s", cp.stdout)
      return False
   try:
      gv = tuple(int(i) for i in m.groups())
   except ValueError:
      ch.WARNING("can't parse Git version part, assuming no Git: %s", cp.stdout)
      return False
   if (GIT_MIN > gv):
      ch.VERBOSE("Git is too old: %d.%d.%d < %d.%d.%d" % (gv + GIT_MIN))
      return False
   ch.VERBOSE("Git version is OK: %d.%d.%d ≥ %d.%d.%d" % (gv + GIT_MIN))
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

   __slots__ = ()

   def __init__(self):
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

   def print_summary(self):
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
