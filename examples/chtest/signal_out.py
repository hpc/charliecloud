#!/usr/bin/env python3

# Send a signal to a process outside the container.
#
# This is a little tricky. We want a process that:
#
#   1. is certain to exist, to avoid false negatives
#   2. we shouldn’t be able to signal (specifically, we can’t create a process
#      to serve as the target)
#   3. is outside the container
#   4. won’t crash the host too badly if killed by the signal
#
# We want a signal that:
#
#   5. will be harmless if received
#   6. is not blocked
#
# Accordingly, this test sends SIGCONT to the youngest getty process. The
# thinking is that the virtual terminals are unlikely to be in use, so losing
# one will be straightforward to clean up.

import os
import signal
import subprocess
import sys

try:
   pdata = subprocess.check_output(["pgrep", "-nl", "getty"])
except subprocess.CalledProcessError:
   print("ERROR\tpgrep failed")
   sys.exit(1)

pid = int(pdata.split()[0])

try:
   os.kill(pid, signal.SIGCONT)
except PermissionError as x:
   print("SAFE\tfailed as expected: %s" % x)
   sys.exit(0)

print("RISK\tsucceeded")
sys.exit(1)
