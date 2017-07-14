load common

setup () {
    if [[ -n $GUEST_USER ]]; then
        # Specific user requested for testing.
        [[ -n $GUEST_GROUP ]]
        GUEST_UID=$(id -u $GUEST_USER)
        GUEST_GID=$(getent group $GUEST_GROUP | cut -d: -f3)
        UID_ARGS="-u $GUEST_UID"
        GID_ARGS="-g $GUEST_GID"
        echo "ID arguments: $GUEST_USER/$GUEST_UID $GUEST_GROUP/$GUEST_GID"
        echo
    else
        # No specific user requested.
        [[ -z $GUEST_GROUP ]]
        GUEST_USER=$(id -un)
        GUEST_UID=$(id -u)
        [[ $GUEST_USER = $USER ]]
        [[ $GUEST_UID -ne 0 ]]
        GUEST_GROUP=$(id -gn)
        GUEST_GID=$(id -g)
        [[ $GUEST_GID -ne 0 ]]
        UID_ARGS=
        GID_ARGS=
        echo "no ID arguments"
        echo
    fi
}

@test 'user and group as specified' {
    g=$(ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- id -un)
    [[ $GUEST_USER = $g ]]
    g=$(ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- id -u)
    [[ $GUEST_UID = $g ]]
    g=$(ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- id -gn)
    [[ $GUEST_GROUP = $g ]]
    g=$(ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- id -g)
    [[ $GUEST_GID = $g ]]
}

@test 'chroot escape' {
    # Try to escape a chroot(2) using the standard approach.
    ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- /test/chroot-escape
}

@test '/dev /proc /sys' {
    # Read some files in /dev, /proc, and /sys that I shouldn't have access to.
    ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- /test/dev_proc_sys.py
}

@test 'filesystem permission enforcement' {
    if [[ $CH_TEST_PERMDIRS = skip ]]; then
        skip
    fi
    for d in $CH_TEST_PERMDIRS; do
        d="$d/perms_test/pass"
        echo "verifying: $d"
          ch-run -t $UID_ARGS $GID_ARGS -b $d $CHTEST_IMG -- \
                 /test/fs_perms.py /mnt/0
    done
}

@test 'mknod(2)' {
    # Make some device files. If this works, we might be able to later read or
    # write them to do things we shouldn't. Try on all mount points.
    ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- \
           sh -c '/test/mknods $(cat /proc/mounts | cut -d" " -f2)'
}

@test 'privileged bind(2)' {
    # Bind to privileged ports on host IP addresses.
    ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- \
           /test/bind_priv.py $(hostname --all-ip-addresses)
}

@test 'remount host root' {
    # Re-mount the root filesystem. Notes:
    #
    #   - Because we have /dev from the host, we don't need to create a new
    #     device node. This makes the test simpler. In particular, we can
    #     treat network and local root the same.
    #
    #   - We leave the filesystem mounted even if successful, again to make
    #     the test simpler. The rest of the tests will ignore it or maybe
    #     over-mount something else.
    ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- \
           sh -c '[ -f /bin/mount -a -x /bin/mount ]'
    dev=$(fgrep ' / ' /proc/mounts | cut -d' ' -f1)
    type=$(fgrep ' / ' /proc/mounts | cut -d' ' -f3)
    opts=$(fgrep ' / ' /proc/mounts | cut -d' ' -f4)
    run ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- \
               /bin/mount -n -o $opts -t $type $dev /oldroot
    echo "$output"
    # return codes from http://man7.org/linux/man-pages/man8/mount.8.html
    # busybox seems to use the same list
    case $status in
        0)      # "success"
            printf 'RISK\tsuccessful mount\n'
            return 1
            ;;
        1)  ;&  # "incorrect invocation of permissions" (we care which)
        255)    # undocumented
            if [[ $output =~ 'ermission denied' ]]; then
                printf 'SAFE\tmount exit %d, permission denied\n' $status
                return 0
            elif [[ $dev = 'rootfs' && $output =~ 'No such device' ]]; then
                printf 'SAFE\tmount exit %d, no such device for rootfs' $status
                return 0
            else
                printf 'RISK\tmount exit %d w/o known explanation\n' $status
                return 1
            fi
            ;;
        32)     # "mount failed"
            printf 'SAFE\tmount exited with code 32\n'
            return 0
            ;;
    esac
    printf 'ERROR\tunknown exit code: %s\n' $status
    return 1
}

@test 'setgroups(2)' {
    # Can we change our supplemental groups?
    ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- /test/setgroups
}

@test 'seteuid(2)' {
    # Try to seteuid(2) to another UID we shouldn't have access to
    ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- /test/setuid
}

@test 'signal process outside container' {
    # Send a signal to a process we shouldn't be able to signal.
    ch-run $UID_ARGS $GID_ARGS $CHTEST_IMG -- /test/signal_out.py
}
