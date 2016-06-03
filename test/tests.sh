TMPDIR=/tmp
DATADIR=/mnt/0
LOGDIR=/mnt/0/err

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
        echo "$setuid_ct setuid, $setgid_ct setgid, $setcap_ct setcap"
    else
        echo "no setuid/setgid/setcap binaries found"
    fi
}

find_suidmounts () {
    findmnt -ln -o target,options | fgrep -v nosuid > $TMPDIR/suidmounts
    suidmount_ct=$(cat $TMPDIR/suidmounts | wc -l)
    if [[ $suidmount_ct -gt 0 ]]; then
        echo "$suidmount_ct filesystems mounted suid"
    else
        echo "no suid filesystems"
    fi
}

find_user_ns () {
    uid_map=$(sed -E 's/\s+/ /g' /proc/self/uid_map)
    if [[ $uid_map = ' 0 0 4294967295' ]]; then
        echo "uid_map is default"
        IN_USERNS=
    else
        echo "in userns (uid_map is not default)"
        IN_USERNS=yes
    fi
}

test_bind_priv () {
    # Bind to privileged ports on host IP addresses.
    ./bind_priv.py $(ls $DATADIR/ip)
}

test_chroot_escape () {
    # Try to escape a chroot(2) using the standard approach.
    ./chroot-escape
}

test_dev_proc_sys () {
    # Read some files in /dev, /proc, /sys that I shouldn't have access to.
    for f in /dev/mem /proc/kcore /sys/devices/cpu/rdpmc; do
        if [[ ! -e $f ]]; then
            printf 'ERROR\t%s does not exist\n' $f
            return
        fi
        out=$(dd if=$f of=/dev/null bs=1 count=1 2>&1)
        echo "$out" 1>&2
        ok_errs='Permission denied|Operation not permitted'  # Chet FAQ #E14
        if [[ ! $out =~ $ok_errs ]]; then
            printf 'RISK\t%s read allowed\n' $f
            return
        fi
    done
    printf 'SAFE\tread not allowed\n'
}

test_fs_perms () {
    # Verify filesystem permission enforcement.
    ./fs_perms.py $(ls -d /mnt/[1-9])
}

test_etc_shadow () {
    # Use passwordless root account /etc/shadow for privilege escalation.
    # (Previously set up in Dockerfile.)
    #
    # WARNING: Do not use this test. It will report false negatives
    # (escalation failed when it succeeds). See comments in su_wrap.py.
    ./su_wrap.py
}

test_mknod () {
    # Try to make some device files. If this works, we might be able to later
    # read or write them to do things we shouldn't. Try on all mount points.
    ./mknods $(cat /proc/mounts | cut -d' ' -f2)
}

test_remount_root () {
    # Re-mount the root filesystem. Notes:
    #
    #   - Because we have /dev from the host, we don't need to create a new
    #     device node. This makes the test simpler. In particular, we can
    #     treat network and local root the same.
    #
    #   - We leave the filesystem mounted even if successful, again to make
    #     the test simpler. The rest of the tests will ignore it or maybe
    #     over-mount something else.
    MOUNT=/bin/mount
    if [[ ! -e $MOUNT ]]; then
        printf 'NOTEST\t%s not found\n' $MOUNT
        return
    fi
    $MOUNT -n \
           -o $(cat $DATADIR/rootopts) \
           -t $(cat $DATADIR/roottype) \
           $(cat $DATADIR/rootdev) \
           /mnt/host
    mountret=$?
    # return codes from http://man7.org/linux/man-pages/man8/mount.8.html
    case $mountret in
        0)      # success
            printf 'RISK'
            ;;
        1)  ;&  # incorrect invocation or permissions
        32)     # mount failed
            printf 'SAFE'
            ;;
        *)
            printf 'ERROR'
            ;;
    esac
    printf '\t%s exited with code %d\n' $MOUNT $mountret
}

test_setgroups () {
    # Can we change our supplemental groups with setgroups(2)?
    ./setgroups
}

test_setuid () {
    # Try to seteuid(2) inappropriately.
    ./setuid
}

test_setuid_bin () {
    # Escalate privilege with a setuid binary.
    ESC_ME=./echo-euid.setuid
    if [[ ! -e $ESC_ME ]]; then
        printf 'NOTEST\t%s not found\n' $ESC_ME
        return
    fi
    esc_euid=$($ESC_ME)
    status=$?
    if [[ $status -ne 0 ]]; then
        printf 'ERROR\t%s exited with status %d\n' $ESC_ME $status
        return
    fi
    if [[ $esc_euid -eq 0 ]]; then
        printf 'RISK\t'
    else
        printf 'SAFE\t'
    fi
    printf 'euid=%s\n' $esc_euid
}

test_signal () {
    # Send a signal to a process outside the container.
    #
    # This is a little tricky. We want a process that:
    #
    #   1. is certain to exist, to avoid false negatives
    #   2. we shouldn't be able to signal (specifically, we can't create a
    #      process to serve as the target)
    #   3. is outside the container
    #   4. won't crash the host too badly if killed by the signal
    #
    # We want a signal that:
    #
    #   5. will be harmless if received
    #   6. is not blocked
    #
    # Accordingly, this test sends SIGCONT to the youngest getty process. The
    # thinking is that the virtual terminals are unlikely to be in use, so
    # losing one will be straightforward to clean up.
    pdata=$(pgrep -nl getty)
    if [[ -z $pdata ]]; then
        printf 'NODEP\tno non-container processes, max pid=%d\n' $(pgrep -n '')
        return
    fi
    pid=$(echo "$pdata" | cut -d' ' -f1)
    killmsg=$(kill -SIGCONT $pid 2>&1)
    killret=$?
    killmsg=$(echo "$killmsg" | sed -r 's/^.+kill: \([0-9]+\) - //')
    case $killret in
        0)
            printf 'RISK\t%s: success' "$pdata"
            ;;
        1)
            printf 'SAFE\t%s: failed: ' "$pdata"
            ;;
        *)
            printf 'ERROR\t%s: unknown: ' "$pdata"
            ;;
    esac
    printf '%s\n' "$killmsg"
}

try () {
    test=$1
    egid=$(id -g)
    shift
    printf "%-15s\t%5d\t%5d\t" $test $EUID $egid
    test_$test "$@" 2>> $LOGDIR/test_$test.$EUID,$egid
}
