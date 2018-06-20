load ../common

@test 'mountns id differs' {
    scope quick
    host_ns=$(stat -Lc '%i' /proc/self/ns/mnt)
    echo "host:  $host_ns"
    guest_ns=$(ch-run $CHTEST_IMG -- stat -Lc '%i' /proc/self/ns/mnt)
    echo "guest: $guest_ns"
    [[ -n $host_ns && -n $guest_ns && $host_ns -ne $guest_ns ]]
}

@test 'userns id differs' {
    scope quick
    host_ns=$(stat -Lc '%i' /proc/self/ns/user)
    echo "host:  $host_userns"
    guest_ns=$(ch-run $CHTEST_IMG -- stat -Lc '%i' /proc/self/ns/user)
    echo "guest: $guest_ns"
    [[ -n $host_ns && -n $guest_ns && $host_ns -ne $guest_ns ]]
}

@test 'distro differs' {
    scope quick
    # This is a catch-all and a bit of a guess. Even if it fails, however, we
    # get an empty string, which is fine for the purposes of the test.
    host_distro=$(  cat /etc/os-release /etc/*-release /etc/*_version \
                  | egrep -m1 '[A-Za-z] [0-9]' \
                  | sed -r 's/^(.*")?(.+)(")$/\2/')
    echo "host: $host_distro"
    guest_expected='Alpine Linux v3.6'
    echo "guest expected: $guest_expected"
    if [[ $host_distro = $guest_expected ]]; then
        skip 'host matches expected guest distro'
    fi
    guest_distro=$(ch-run $CHTEST_IMG -- \
                          cat /etc/os-release \
                   | fgrep PRETTY_NAME \
                   | sed -r 's/^(.*")?(.+)(")$/\2/')
    echo "guest: $guest_distro"
    [[ $guest_distro = $guest_expected ]]
    [[ $guest_distro != $host_distro ]]
}

@test 'user and group match host' {
    scope quick
    host_uid=$(id -u)
    guest_uid=$(ch-run $CHTEST_IMG -- id -u)
    [[ $host_uid = $guest_uid ]]
    host_pgid=$(id -g)
    guest_pgid=$(ch-run $CHTEST_IMG -- id -g)
    [[ $host_pgid = $guest_pgid ]]
    host_username=$(id -un)
    guest_username=$(ch-run $CHTEST_IMG -- id -un)
    [[ $host_username = $guest_username ]]
    host_pgroup=$(id -gn)
    guest_pgroup=$(ch-run $CHTEST_IMG -- id -gn)
    [[ $host_pgroup = $guest_pgroup ]]
}
