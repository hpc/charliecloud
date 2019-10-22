load ../common

@test 'ch-run refuses to run if setgid' {
    scope quick
    ch_run_tmp=$BATS_TMPDIR/ch-run.setgid
    gid=$(id -g)
    gid2=$(id -G | cut -d' ' -f2)
    echo "gids: ${gid} ${gid2}"
    [[ $gid != "$gid2" ]]
    cp -a "$ch_runfile" "$ch_run_tmp"
    ls -l "$ch_run_tmp"
    chgrp "$gid2" "$ch_run_tmp"
    chmod g+s "$ch_run_tmp"
    ls -l "$ch_run_tmp"
    [[ -g $ch_run_tmp ]]
    run "$ch_run_tmp" --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *': error ('* ]]
    rm "$ch_run_tmp"
}

@test 'ch-run refuses to run if setuid' {
    scope quick
    [[ -n $ch_have_sudo ]] || skip 'sudo not available'
    ch_run_tmp=$BATS_TMPDIR/ch-run.setuid
    cp -a "$ch_runfile" "$ch_run_tmp"
    ls -l "$ch_run_tmp"
    sudo chown root "$ch_run_tmp"
    sudo chmod u+s "$ch_run_tmp"
    ls -l "$ch_run_tmp"
    [[ -u $ch_run_tmp ]]
    run "$ch_run_tmp" --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *': error ('* ]]
    sudo rm "$ch_run_tmp"
}

@test 'ch-run as root: --version and --test' {
    scope quick
    [[ -n $ch_have_sudo ]] || skip 'sudo not available'
    sudo "$ch_runfile" --version
    sudo "$ch_runfile" --help
}

@test 'ch-run as root: run image' {
    scope standard
    # Running an image should work as root, but it doesn't, and I'm not sure
    # why, so skip this test. This fails in the test suite with:
    #
    #   ch-run: couldn't resolve image path: No such file or directory (ch-run.c:139:2)
    #
    # but when run manually (with same arguments?) it fails differently with:
    #
    #   $ sudo bin/ch-run $ch_imgdir/chtest -- true
    #   ch-run: [...]/chtest: Permission denied (ch-run.c:195:13)
    #
    skip 'issue #76'
    sudo "$ch_runfile" "$ch_timg" -- true
}

@test 'ch-run as root: root with non-zero gid refused' {
    scope standard
    [[ -n $ch_have_sudo ]] || skip 'sudo not available'
    [[ -z $TRAVIS ]] || skip 'not permitted on Travis'
    # Allowing sudo to user root but group non-root is an unusual
    # configuration. You need e.g. "%foo ALL=(ALL:ALL)" instead of the more
    # common "%foo ALL=(ALL)". Because this is a rather esoteric test, we want
    # to skip in the common configuration but still be reliably tested.
    # Because Travis doesn't do this, he best I could come up with is to
    # insist the test run at LANL (and fail if sudo is not configured
    # correctly). See issue #485.
    if    ! (sudo -u root -g "$(id -gn)" true) \
       && [[ $(hostname --fqdn) != *'.lanl.gov' ]]; then
        skip "sudo not configured for user root and group non-root"
    fi
    run sudo -u root -g "$(id -gn)" "$ch_runfile" -v --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error ('* ]]
}
