#!/usr/bin/env python3

import os.path
import sys

# File in /sys seem to vary between Linux systems. Thus, try a few candidates
# and use the first one that exists. What we want is any file under /sys with
# permissions root:root -rw------- that's in a directory readable and
# executable by unprivileged users, so we know we're testing permissions on
# the file rather than any of its containing directories. This may help:
#
#   $ find /sys -type f -a -perm 600 -ls
#
sys_file = None
for f in ("/sys/devices/cpu/rdpmc",
          "/sys/kernel/mm/page_idle/bitmap",
          "/sys/module/nf_conntrack_ipv4/parameters/hashsize",
          "/sys/kernel/slab/request_sock_TCP/red_zone"):
   if (os.path.exists(f)):
      sys_file = f
      break

if (sys_file is None):
   print("ERROR\tno test candidates in /sys exist")
   sys.exit(1)

problem_ct = 0
for f in ("/dev/mem", "/proc/kcore", sys_file):
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
