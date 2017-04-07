load common

@test 'prepare images directory' {
    if [[ -e $IMGDIR ]]; then
        # Images directory exists. If all it contains is Charliecloud images
        # or supporting directories, then we're ok; remove the images (this
        # makes test-build and test-run follow the same path when run on the
        # same or different machines). Otherwise, error.
        for i in $IMGDIR/*; do
            if [[ -d $i && -f $i/WEIRD_AL_YANKOVIC ]]; then
                echo "found image $i; removing"
                rm -Rf --one-file-system $i
            else
                echo "found non-image $i; aborting"
                false
            fi
        done
    fi
    mkdir -p $IMGDIR
    mkdir -p $IMGDIR/bind1
    touch $IMGDIR/bind1/WEIRD_AL_YANKOVIC  # fool logic above
    touch $IMGDIR/bind1/file1
    mkdir -p $IMGDIR/bind2
    touch $IMGDIR/bind2/WEIRD_AL_YANKOVIC
    touch $IMGDIR/bind2/file2
}

@test 'executables --help' {
    ch-tar2dir --help
    ch-run --help
    ch-ssh --help
}

@test 'setuid bit matches --is-setuid' {
    test $CH_RUN_FILE -ef $(which ch-run)
    [[ -e $CH_RUN_FILE ]]
    ls -l $CH_RUN_FILE
    if ( ch-run --is-setuid ); then
        [[ -n $CH_RUN_SETUID ]]
        [[ -u $CH_RUN_FILE ]]
        [[ $(stat -c %U $CH_RUN_FILE) = root ]]
    else
        [[ -z $CH_RUN_SETUID ]]
        [[ ! -u $CH_RUN_FILE ]]
        #[[ $(stat -c %U $CH_RUN_FILE) != root ]]
    fi
}

@test 'setgid bit is off' {
    [[ -e $CH_RUN_FILE ]]
    [[ ! -g $CH_RUN_FILE ]]
    #[[ $(stat -c %G $CH_RUN_FILE) != root ]]
}

@test 'ch-run refuses to run if setgid' {
    CH_RUN_TMP=$BATS_TMPDIR_PRIVATE/ch-run.setgid
    GID=$(id -g)
    GID2=$(id -G | cut -d' ' -f2)
    echo "GIDs: $GID $GID2"
    [[ $GID != $GID2 ]]
    cp -a $CH_RUN_FILE $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    chgrp $GID2 $CH_RUN_TMP
    chmod g+s $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    [[ -g $CH_RUN_TMP ]]
    run $CH_RUN_TMP --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'ch-run.setgid: error: Success' ]]
    rm $CH_RUN_TMP
}

@test 'ch-run refuses to run if setuid' {
    [[ -n $CH_RUN_SETUID ]] && skip
    CH_RUN_TMP=$BATS_TMPDIR_PRIVATE/ch-run.setuid
    cp -a $CH_RUN_FILE $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    sudo chown root $CH_RUN_TMP
    sudo chmod u+s $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    [[ -u $CH_RUN_TMP ]]
    run $CH_RUN_TMP --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'ch-run.setuid: error: Success' ]]
    sudo rm $CH_RUN_TMP
}

@test 'ch-run -u and -g refused in setuid mode' {
    [[ -z $CH_RUN_SETUID ]] && skip
    run ch-run -u 65534
    echo "$output"
    [[ $status -eq 64 ]]
    [[ $output =~ "ch-run: invalid option -- 'u'" ]]
    run ch-run -g 65534
    echo "$output"
    [[ $status -eq 64 ]]
    [[ $output =~ "ch-run: invalid option -- 'g'" ]]
}

@test 'syscalls/pivot_root' {
    [[ -n $CH_RUN_SETUID ]] && skip
    cd ../examples/syscalls
    ./pivot_root
}

@test 'unpack chtest image' {
    ch-tar2dir $CHTEST_TARBALL $CHTEST_IMG
}

@test 'workaround for /bin not in $PATH' {
    echo "$PATH"
    # if /bin is in $PATH, latter passes through unchanged
    PATH2="$CH_BIN:/bin:/usr/bin"
    echo $PATH2
    PATH=$PATH2 run ch-run $CHTEST_IMG -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = $PATH2 ]]
    PATH2="/bin:$CH_BIN:/usr/bin"
    echo $PATH2
    PATH=$PATH2 run ch-run $CHTEST_IMG -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = $PATH2 ]]
    # if /bin isn't in $PATH, former is added to end
    PATH2="$CH_BIN:/usr/bin"
    echo $PATH2
    PATH=$PATH2 run ch-run $CHTEST_IMG -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = $PATH2:/bin ]]
}

@test 'mountns id differs' {
    host_ns=$(stat -Lc '%i' /proc/self/ns/mnt)
    echo "host:  $host_ns"
    guest_ns=$(ch-run $CHTEST_IMG -- stat -Lc '%i' /proc/self/ns/mnt)
    echo "guest: $guest_ns"
    [[ -n $host_ns && -n $guest_ns && $host_ns -ne $guest_ns ]]
}

@test 'userns id differs' {
    [[ -n $CH_RUN_SETUID ]] && skip
    host_ns=$(stat -Lc '%i' /proc/self/ns/user)
    echo "host:  $host_userns"
    guest_ns=$(ch-run $CHTEST_IMG -- stat -Lc '%i' /proc/self/ns/user)
    echo "guest: $guest_ns"
    [[ -n $host_ns && -n $guest_ns && $host_ns -ne $guest_ns ]]
}

@test 'distro differs' {
    # This is a catch-all and a bit of a guess. Even if it fails, however, we
    # get an empty string, which is fine for the purposes of the test.
    echo hello world
    host_distro=$(  cat /etc/os-release /etc/*-release /etc/*_version \
                  | egrep -m1 '[A-Za-z] [0-9]' \
                  | sed -r 's/^(.*")?(.+)(")$/\2/')
    echo "host: $host_distro"
    guest_expected='Alpine Linux v3.5'
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

@test 'image mounted read-only' {
    run ch-run $CHTEST_IMG sh <<EOF
set -e
test -w /WEIRD_AL_YANKOVIC
dd if=/dev/zero bs=1 count=1 of=/WEIRD_AL_YANKOVIC
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output =~ 'Read-only file system' ]]
}

@test '--dir' {
    ch-run -d $IMGDIR/bind1 $CHTEST_IMG -- cat /mnt/0/file1
    ch-run -d $IMGDIR/bind1 -d $IMGDIR/bind2 $CHTEST_IMG -- cat /mnt/1/file2
}

@test 'permissions test directories exist' {
    if [[ $CH_TEST_PERMDIRS = skip ]]; then
        skip
    fi
    for d in $CH_TEST_PERMDIRS; do
        d=$d/perms_test
        echo $d
        test -d $d
        test -d $d/pass
        test -f $d/pass/file
        test -d $d/nopass
        test -d $d/nopass/dir
        test -f $d/nopass/file
    done
}

