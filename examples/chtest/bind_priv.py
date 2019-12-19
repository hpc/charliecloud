#!/usr/bin/env python3

# This script tries to bind to a privileged port on each of the IP addresses
# specified on the command line.

import errno
import socket
import sys

PORT = 7  # echo

results = dict()

try:
   for ip in sys.argv[1:]:
      s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
      try:
         s.bind((ip, PORT))
      except OSError as x:
         if (x.errno in (errno.EACCES, errno.EADDRNOTAVAIL)):
            results[ip] = x.errno
         else:
            raise
      else:
         results[ip] = 0
except Exception as x:
   print('ERROR\texception: %s' % x)
   rc = 1
else:
   if (len(results) < 1):
      print('ERROR\tnothing to test', end='')
      rc = 1
   elif (len(set(results.values())) != 1):
      print('ERROR\tmixed results: ', end='')
      rc = 1
   else:
      result = next(iter(results.values()))
      if (result != 0):
         print('SAFE\t%d (%s) ' % (result, errno.errorcode[result]), end='')
         rc = 0
      else:
         print('RISK\tsuccessful bind ', end='')
         rc = 1
   explanation = ' '.join('%s=%d' % (ip, e)
                          for (ip, e) in sorted(results.items()))
   print(explanation)

sys.exit(rc)
