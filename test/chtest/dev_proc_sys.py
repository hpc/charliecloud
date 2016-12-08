#!/usr/bin/env python3

import sys

# other candidates:
#   /sys/devices/cpu/rdpmc (not in Travis)
#   /sys/kernel/slab/*/cpu_partial (how to make sure * is stable?)

problem_ct = 0
for f in ("/dev/mem", "/proc/kcore", "/sys/kernel/mm/page_idle/bitmap"):
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
