TMPDIR=/tmp
LOGDIR=/0/err

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

# NOTE: Test functions should be named with a maximum of FIXME characters for
# proper alignment in output.

test_bind_priv () {
    # Bind to privileged ports on host IP addresses.
    false
}

test_chroot_escape () {
    # Try to escape a chroot(2) using the standard approach.
    ./chroot-escape
}

test_dev_proc_sys () {
    # Read some files in /dev, /proc, /sys that I shouldn't have access to.
    #read /dev/mem, /proc/kcore, /sys/devices/cpu/rdpmc
    false
}

test_fs_perms () {
    # Verify filesystem permission enforcement.
    false
}

test_etc_passwd () {
    # Change /etc/passwd.
    false
}

test_my_shadow () {
    # Use my /etc/shadow for privilege escalation.
    false
}

test_remount_root () {
    # Re-mount the root filesystem via a new device node.
    false
}

test_serial () {
    # Read from a hardware device (serial port) I shouldn't have access to.
    false
}

test_setuid () {
    # Escalate privilege with a setuid binary.
    ESC_ME=./echo-euid.setuid
    if [[ -e $ESC_ME ]]; then
        esc_euid=$($ESC_ME)
        status=$?
        if [[ $status -ne 0 ]]; then
            printf 'ERROR\t%s exited with status %d\n' $ESC_ME $status
        else
            if [[ $esc_euid -eq 0 ]]; then
                printf 'RISK\t'
            else
                printf 'SAFE\t'
            fi
            printf 'euid=%s\n' $esc_euid
        fi
    else
        printf 'NOTEST\t%s not found\n' $ESC_ME
    fi
}

test_signal_udevd () {
    # Send a signal to a process I don't own (SIGCONT to udevd).
    false
}

try () {
    test=$1
    shift
    if [[ $EUID -eq 0 ]]; then
        priv=p
    else
        priv=u
    fi
    printf "%-15s\t%s\t" $test $priv
    test_$test "$@" 2>> $LOGDIR/test_$test.$priv.err
}
