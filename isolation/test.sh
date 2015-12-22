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
#   1. Test name
#   2. Colon
#   3. "priv" (privileged) or "unpr" (unprivileged)
#   4. Colon
#   5. Result (see below)
#   6. Additional details beginning with a space (optional)
#
# Result is one of:
#
#   ISOLATED      Host resource could not be accessed
#   NOT-ISOLATED  Host resource could be accessed
#   ERROR         Test could not be performed (this should not happen)
#   INVALID       Test is inappropriate for some reason (may or may not be OK)
#
# We deliberately do not use "ok/fail" or similar because NOT-ISOLATED is not
# necessarily a failure.
#
# Lines beginning with "#" are informational.
#
# Additional chatter goes to stderr.

TMPDIR=/tmp

main () {
    print_info
    echo '# done'
}

find_setuid () {
    find -P / -xdev ! -readable -prune -o -type f -perm /u=s -print \
         > $TMPDIR/setuid_files
    find -P / -xdev ! -readable -prune -o -type f -perm /g=s -print \
         > $TMPDIR/setgid_files
    # Only search /usr because getcap cannot stop at filesystem boundaries,
    # and we don't know what big host filesystems are mounted.
    getcap -r /usr > $TMPDIR/setcap_files 2> $TMPDIR/setcap_err
    setuid_ct=$(cat $TMPDIR/setuid_files | wc -l)
    setgid_ct=$(cat $TMPDIR/setgid_files | wc -l)
    setcap_ct=$(cat $TMPDIR/setcap_files | wc -l)
    if [[ $setuid_ct -gt 0 || $setgid_ct -gt 0 ]]; then
        echo "unsafe: $setuid_ct setuid, $setgid_ct setgid, $setcap_ct setcap"
    else
        echo "safe"
    fi
}

find_suidmounts () {
    findmnt -ln -o target,options | fgrep -v nosuid > $TMPDIR/suidmounts
    suidmount_ct=$(cat $TMPDIR/suidmounts | wc -l)
    if [[ $suidmount_ct -gt 0 ]]; then
        echo "unsafe: $suidmount_ct filesystems mounted suid"
    else
        echo "safe"
    fi
}

find_user_ns () {
    uid_map=$(sed -E 's/\s+/ /g' /proc/self/uid_map)
    if [[ $uid_map = ' 0 0 4294967295' ]]; then
        echo "unsafe: uid_map is default"
    else
        echo "safe: uid_map is not default"
    fi
}

print_info () {
    echo -n '# running privileged:  '
    [[ $EUID == 0 ]] && echo "unsafe: euid=$EUID" || echo "safe: euid=$EUID"
    echo -n '# setuid binaries:     '
    find_setuid /
    echo -n '# suid filesystems:    '
    find_suidmounts
    echo -n '# user namespace:      '
    find_user_ns
}


main
