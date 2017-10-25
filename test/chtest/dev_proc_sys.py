#!/usr/bin/env python3

import os.path
import sys

# File in /sys seem to vary between Linux systems. Thus, try a few candidates
# and use the first one that exists. What we want is any file under /sys with
# permissions root:root -rw-------.
sys_file = None
for f in ("/sys/devices/cpu/rdpmc",
          "/sys/kernel/mm/page_idle/bitmap",
          "/sys/kernel/slab/request_sock_TCP/red_zone"):
   if (os.path.exists(f)):
      sys_file = f
      break

if sys_file is None:
   print("WARNING\t No sys_file found to test")

problem_ct = 0
for f in ("/dev/mem", "/proc/kcore", sys_file):
   if f is not None:
      try:
         open(f, "rb").read(1)
         print("RISK\t%s: read allowed" % f)
         problem_ct += 1
      except PermissionError:
         print("SAFE\t%s: read not allowed" % f)
      except OSError as x:
         print("ERROR\t%s: exception: %s" % (f, x))
         problem_ct += 1

sys.exit(problem_ct != 0)
