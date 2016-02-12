#!/bin/bash

# Run this test script inside a container to evaluate its isolation. Each test
# prints a single line on stdout. This line contains:
#
#   1. test name
#   2. tab
#   3. "p" (privileged) or "u" (unprivileged)
#   4. tab
#   5. result (see below)
#   6. additional details beginning with a tab (optional)
#
# Result is one of:
#
#   SAFE   Host resource could not be accessed
#   RISK   Host resource could be accessed or other risky condition
#   ERROR  Unexpected condition while testing (this should not happen)
#   NODEP  Test not performed due to missing dependency (may or may not be OK)
#
# We deliberately do not use "ok/fail" or similar because NOT-ISOLATED is not
# necessarily a failure.
#
# Lines beginning with "#" are informational. Additional chatter goes to
# stderr.
#
# Originally, when invoked as root, this script ran the tests, dropped
# privileges using su, and ran the tests again. However, setgroups(2) is
# completely unavailable in some containers, and so su doesn't work.
# Therefore, the caller must run two test suites to evaluate privileged and
# unprivileged mode operations.

set -e

cd $(dirname $0)
. tests.sh

echo
echo '### Starting'

printf '# running privileged:  '
[[ $EUID == 0 ]] && echo "unsafe: euid=$EUID" || echo "safe: euid=$EUID"
printf '# setuid binaries:     '
find_setuid /
printf '# suid filesystems:    '
find_suidmounts
printf '# user namespace:      '
find_user_ns

if [[ $EUID -eq 0 ]]; then
    ./test-operations.sh
else
    ./test-escalation.sh
    ./test-operations.sh
fi

echo
echo '### Done'
