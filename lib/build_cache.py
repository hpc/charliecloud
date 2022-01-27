import enum
import re

import charliecloud as ch


## Constants ##

# Required versions.
GIT_MIN = ( 2, 34, 1)
GIT2DOT_MIN = (0, 8, 3)


## Globals ##

# Root state ID.
root_id = None
ROOT_ID = '4a4f-5345-0043-4150-4142-4c41-4e43-4100'


## Classes ##


## Supporting functions ##

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
   # set cache appropriately
   #global cache
   #cache = ...
