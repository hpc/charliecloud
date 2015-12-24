#!/usr/bin/env python3

# This script tries to use su to gain root privileges, assuming that
# /etc/shadow has been changed such that no password is required. It uses
# pexpect to emulate the terminal that su requires.
#
# WARNING: This does not work. For example:
#
#   $ whoami ; echo $UID EUID
#   reidpr
#   1001 1001
#   $ /bin/su -c whoami
#   root
#   $ ./su_wrap.py 2>> /dev/null
#   SAFE	escalation failed: empty password rejected
#
# That is, manual su can escalate without a password (and doesn't without the
# /etc/shadow hack), but when this program tries to do apparently the same
# thing, su wants a password.
#
# I have not been able to track down why this happens. I suspect that PAM has
# some extra smarts about TTY that causes it to ask for a password under
# pexpect. I'm leaving the code in the repository in case some future person
# can figure it out.

import sys
import pexpect

# Invoke su. This will do one of three things:
#
#   1. Print 'root'; the escalation was successful.
#   2. Ask for a password; the escalation was unsuccessful.
#   3. Something else; this is an error.
#
p = pexpect.spawn('/bin/su', ['-c', 'whoami'], timeout=5,
                  encoding='UTF-8', logfile=sys.stderr)
i = p.expect_exact(['root', 'Password:'])
try:
   if (i == 0):       # printed "root"
      print('RISK\tescalation successful: no password requested')
   elif (i == 1):     # asked for password
      p.sendline()    # try empty password
      i = p.expect_exact(['root', 'Authentication failure'])
      if (i == 0):    # printed "root"
         print('RISK\tescalation successful: empty password accepted')
      elif (i == 1):  # explicit failure
         print('SAFE\tescalation failed: empty password rejected')
      else:
         assert False
   else:
      assert False
except p.EOF:
   print('ERROR\tsu exited unexpectedly')
except p.TIMEOUT:
   print('ERROR\ttimed out waiting for su')
except AssertionError:
   print('ERROR\tassertion failed')
