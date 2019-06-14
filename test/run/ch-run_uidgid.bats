load ../common

setup () {
    scope standard
    if [[ -n $GUEST_USER ]]; then
        # Specific user requested for testing.
        [[ -n $GUEST_GROUP ]]
        guest_uid=$(id -u "$GUEST_USER")
        guest_gid=$(getent group "$GUEST_GROUP" | cut -d: -f3)
        uid_args="-u ${guest_uid}"
        gid_args="-g ${guest_gid}"
        echo "ID args: ${GUEST_USER}/${guest_uid} ${GUEST_GROUP}/${guest_gid}"
        echo
    else
        # No specific user requested.
        [[ -z $GUEST_GROUP ]]
        GUEST_USER=$(id -un)
        guest_uid=$(id -u)
        [[ $GUEST_USER = "$USER" ]]
        [[ $guest_uid -ne 0 ]]
        GUEST_GROUP=$(id -gn)
        guest_gid=$(id -g)
        [[ $guest_gid -ne 0 ]]
        uid_args=
        gid_args=
        echo "no ID arguments"
        echo
    fi
}

@test 'user and group as specified' {
    g=$(ch-run $uid_args $gid_args "$ch_timg" -- id -un)
    [[ $GUEST_USER = "$g" ]]
    g=$(ch-run $uid_args $gid_args "$ch_timg" -- id -u)
    [[ $guest_uid = "$g" ]]
    g=$(ch-run $uid_args $gid_args "$ch_timg" -- id -gn)
    [[ $GUEST_GROUP = "$g" ]]
    g=$(ch-run $uid_args $gid_args "$ch_timg" -- id -g)
    [[ $guest_gid = "$g" ]]
}

@test 'chroot escape' {
    # Try to escape a chroot(2) using the standard approach.
    ch-run $uid_args $gid_args "$ch_timg" -- /test/chroot-escape
}

@test '/dev /proc /sys' {
    # Read some files in /dev, /proc, and /sys that I shouldn't have access to.
    ch-run $uid_args $gid_args "$ch_timg" -- /test/dev_proc_sys.py
}

@test 'filesystem permission enforcement' {
    [[ $CH_TEST_PERMDIRS = skip ]] && skip 'user request'
    for d in $CH_TEST_PERMDIRS; do
        d="${d}/perms_test/pass"
        echo "verifying: ${d}"
          ch-run --no-home --private-tmp \
                 $uid_args $gid_args -b "$d" "$ch_timg" -- \
                 /test/fs_perms.py /mnt/0
    done
}

@test 'mknod(2)' {
    # Make some device files. If this works, we might be able to later read or
    # write them to do things we shouldn't. Try on all mount points.
    # shellcheck disable=SC2016
    ch-run $uid_args $gid_args "$ch_timg" -- \
           sh -c '/test/mknods $(cat /proc/mounts | cut -d" " -f2)'
}

@test 'privileged IPv4 bind(2)' {
    # Bind to privileged ports on all host IPv4 addresses.
    #
    # Some supported distributions don't have "hostname --all-ip-addresses".
    # Hence the awk voodoo.
    addrs=$(ip -o addr | awk '/inet / {gsub(/\/.*/, " ",$4); print $4}')
    # shellcheck disable=SC2086
    ch-run $uid_args $gid_args "$ch_timg" -- /test/bind_priv.py $addrs
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
    ch-run $uid_args $gid_args "$ch_timg" -- \
           sh -c '[ -f /bin/mount -a -x /bin/mount ]'
    dev=$(findmnt -n -o SOURCE -T /)
    type=$(findmnt -n -o FSTYPE -T /)
    opts=$(findmnt -n -o OPTIONS -T /)
    run ch-run $uid_args $gid_args "$ch_timg" -- \
               /bin/mount -n -o "$opts" -t "$type" "$dev" /mnt/0
    echo "$output"
    # return codes from http://man7.org/linux/man-pages/man8/mount.8.html
    # busybox seems to use the same list
    case $status in
        0)      # "success"
            info 'RISK    successful mount'
            return 1
            ;;
        1)   ;&  # "incorrect invocation or permissions" (we care which)
        111) ;&  # undocumented
        255)     # undocumented
            if [[ $output = *'ermission denied'* ]]; then
                printf 'SAFE\tmount exit %d, permission denied\n' "$status"
                return 0
            elif [[ $dev = 'rootfs' && $output =~ 'No such device' ]]; then
                printf 'SAFE\tmount exit %d, no such device' "$status"
                return 0
            else
                printf 'RISK\tmount exit %d w/o known explanation\n' "$status"
                return 1
            fi
            ;;
        32)     # "mount failed"
            printf 'SAFE\tmount exited with code 32\n'
            return 0
            ;;
    esac
    printf 'ERROR\tunknown exit code: %s\n' "$status"
    return 1
}

@test 'setgroups(2)' {
    # Can we change our supplemental groups?
    ch-run $uid_args $gid_args "$ch_timg" -- /test/setgroups
}

@test 'seteuid(2)' {
    # Try to seteuid(2) to another UID we shouldn't have access to
    ch-run $uid_args $gid_args "$ch_timg" -- /test/setuid
}

@test 'signal process outside container' {
    # Send a signal to a process we shouldn't be able to signal.
    [[ $(pgrep -c getty) -eq 0 ]] && skip 'no getty process found'
    ch-run $uid_args $gid_args "$ch_timg" -- /test/signal_out.py
}
