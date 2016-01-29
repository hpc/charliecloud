#!/bin/bash

# Run this test script inside a container to evaluate its isolation. There are
# three basic groups of tests:
#
#   1. Privileged tests. These are run only if the script starts as root, to
#      simulate a successful privilege escalation.
#
#   2. Privilege escalation tests.
#
#   3. Unprivileged tests. These test what can be done without an escalation.
#
# Each test prints a single line on stdout. This line contains:
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
# Lines beginning with "#" are informational.
#
# Additional chatter goes to stderr.

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
    # Bash does not know how to drop privileges. So, we run three sub-scripts
    # with different privilege levels. Note that su complains about
    # "Authentication failure" but ignores the problem; we don't want this in
    # the output, but we also don't want to suppress other errors.
    TEST_USER=$(cat /mnt/0/user)
    SU=/bin/su
    if [[ ! -e $SU ]]; then
        echo "$SU missing, aborting"
        exit 1
    fi
    ./test-operations.sh
    $SU -m -c './test-escalation.sh' $TEST_USER 2>> $LOGDIR/su.err
    $SU -m -c './test-operations.sh' $TEST_USER 2>> $LOGDIR/su.err
else
    echo '# skipping privileged tests'
    ./test-escalation.sh
    ./test-operations.sh
fi

echo
echo '### Done'
