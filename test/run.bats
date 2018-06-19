load common

@test 'prepare images directory' {
    scope quick
    shopt -s nullglob  # globs that match nothing yield empty string
    if [[ -e $IMGDIR ]]; then
        # Images directory exists. If all it contains is Charliecloud images
        # or supporting directories, or nothing, then we're ok. Remove any
        # images (this makes test-build and test-run follow the same path when
        # run on the same or different machines). Otherwise, error.
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

@test 'permissions test directories exist' {
    scope standard
    [[ $CH_TEST_PERMDIRS = skip ]] && skip 'user request'
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

@test 'executables --help' {
    scope standard
    ch-tar2dir --help
    ch-run --help
    ch-ssh --help
}

@test 'syscalls/pivot_root' {
    scope quick
    cd ../examples/syscalls
    ./pivot_root
}

@test 'unpack chtest image' {
    scope quick
    if ( image_ok $CHTEST_IMG ); then
        # image exists, remove so we can test new unpack
        rm -Rf --one-file-system $CHTEST_IMG
    fi
    ch-tar2dir $CHTEST_TARBALL $IMGDIR  # new unpack
    image_ok $CHTEST_IMG
    ch-tar2dir $CHTEST_TARBALL $IMGDIR  # overwrite
    image_ok $CHTEST_IMG
}

@test 'ch-run refuses to run if setgid' {
    scope quick
    CH_RUN_TMP=$BATS_TMPDIR/ch-run.setgid
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
    [[ $output =~ ': error (' ]]
    rm $CH_RUN_TMP
}

@test 'ch-run refuses to run if setuid' {
    scope quick
    [[ -n $CHTEST_HAVE_SUDO ]] || skip 'sudo not available'
    CH_RUN_TMP=$BATS_TMPDIR/ch-run.setuid
    cp -a $CH_RUN_FILE $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    sudo chown root $CH_RUN_TMP
    sudo chmod u+s $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    [[ -u $CH_RUN_TMP ]]
    run $CH_RUN_TMP --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ ': error (' ]]
    sudo rm $CH_RUN_TMP
}

@test 'ch-run as root: --version and --test' {
    scope standard
    [[ -n $CHTEST_HAVE_SUDO ]] || skip 'sudo not available'
    sudo $CH_RUN_FILE --version
    sudo $CH_RUN_FILE --help
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
    #   $ sudo bin/ch-run $CH_TEST_IMGDIR/chtest -- true
    #   ch-run: [...]/chtest: Permission denied (ch-run.c:195:13)
    #
    skip 'issue #76'
    sudo $CH_RUN_FILE $CHTEST_IMG -- true
}

@test 'ch-run as root: root with non-zero GID refused' {
    scope standard
    [[ -n $CHTEST_HAVE_SUDO ]] || skip 'sudo not available'
    [[ -z $TRAVIS ]] || skip 'not permitted on Travis'
    run sudo -u root -g $(id -gn) $CH_RUN_FILE -v --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'error (' ]]
}

@test 'ch-tar2dir errors' {
    scope quick
    # tarball doesn't exist
    run ch-tar2dir does_not_exist.tar.gz $IMGDIR
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = "can't read does_not_exist.tar.gz" ]]

    # tarball exists but isn't readable
    touch $BATS_TMPDIR/unreadable.tar.gz
    chmod 000 $BATS_TMPDIR/unreadable.tar.gz
    run ch-tar2dir $BATS_TMPDIR/unreadable.tar.gz $IMGDIR
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = "can't read $BATS_TMPDIR/unreadable.tar.gz" ]]
}

@test 'workaround for /bin not in $PATH' {
    scope quick
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

@test '$PATH unset' {
    scope standard
    BACKUP_PATH=$PATH
    unset PATH
    run $CH_RUN_FILE $CHTEST_IMG -- \
        /usr/bin/python3 -c 'import os; print(os.getenv("PATH") is None)'
    PATH=$BACKUP_PATH
    echo "$output"
    [[ $status -eq 0 ]]
    r=': \$PATH not set'
    [[ $output =~ $r ]]
    [[ $output =~ 'True' ]]
}

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

@test 'mount image read-only' {
    scope quick
    run ch-run $CHTEST_IMG sh <<EOF
set -e
test -w /WEIRD_AL_YANKOVIC
dd if=/dev/zero bs=1 count=1 of=/WEIRD_AL_YANKOVIC
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output =~ 'Read-only file system' ]]
}

@test 'mount image read-write' {
    scope quick
    ch-run -w $CHTEST_IMG -- sh -c 'echo writable > write'
    ch-run -w $CHTEST_IMG rm write
}

@test 'ch-run --bind' {
    scope quick
    # one bind, default destination (/mnt/0)
    ch-run -b $IMGDIR/bind1 $CHTEST_IMG -- cat /mnt/0/file1
    # one bind, explicit destination
    ch-run -b $IMGDIR/bind1:/mnt/9 $CHTEST_IMG -- cat /mnt/9/file1

    # two binds, default destination
    ch-run -b $IMGDIR/bind1 -b $IMGDIR/bind2 $CHTEST_IMG \
           -- cat /mnt/0/file1 /mnt/1/file2
    # two binds, explicit destinations
    ch-run -b $IMGDIR/bind1:/mnt/8 -b $IMGDIR/bind2:/mnt/9 $CHTEST_IMG \
           -- cat /mnt/8/file1 /mnt/9/file2
    # two binds, default/explicit
    ch-run -b $IMGDIR/bind1 -b $IMGDIR/bind2:/mnt/9 $CHTEST_IMG \
           -- cat /mnt/0/file1 /mnt/9/file2
    # two binds, explicit/default
    ch-run -b $IMGDIR/bind1:/mnt/8 -b $IMGDIR/bind2 $CHTEST_IMG \
           -- cat /mnt/8/file1 /mnt/1/file2

    # bind one source at two destinations
    ch-run -b $IMGDIR/bind1:/mnt/8 -b $IMGDIR/bind1:/mnt/9 $CHTEST_IMG \
           -- diff -u /mnt/8/file1 /mnt/9/file1
    # bind two sources at one destination
    ch-run -b $IMGDIR/bind1:/mnt/9 -b $IMGDIR/bind2:/mnt/9 $CHTEST_IMG \
           -- sh -c '[ ! -e /mnt/9/file1 ] && cat /mnt/9/file2'

    # omit tmpfs at /home, which shouldn't be empty
    ch-run --no-home $CHTEST_IMG -- cat /home/overmount-me
    # overmount tmpfs at /home
    ch-run -b $IMGDIR/bind1:/home $CHTEST_IMG -- cat /home/file1
    # bind to /home without overmount
    ch-run --no-home -b $IMGDIR/bind1:/home $CHTEST_IMG -- cat /home/file1
    # omit default /home, with unrelated --bind
    ch-run --no-home -b $IMGDIR/bind1 $CHTEST_IMG -- cat /mnt/0/file1
}

@test 'ch-run --bind errors' {
    scope quick

    # too many binds (11)
    run ch-run -b0 -b1 -b2 -b3 -b4 -b5 -b6 -b7 -b8 -b9 -b10 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--bind can be used at most 10 times' ]]

    # no argument to --bind
    run ch-run $CHTEST_IMG -b
    echo "$output"
    [[ $status -eq 64 ]]
    [[ $output =~ 'option requires an argument' ]]

    # empty argument to --bind
    run ch-run -b '' $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--bind: no source provided' ]]

    # source not provided
    run ch-run -b :/mnt/9 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--bind: no source provided' ]]

    # destination not provided
    run ch-run -b $IMGDIR/bind1: $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--bind: no destination provided' ]]

    # source does not exist
    run ch-run -b $IMGDIR/hoops $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/hoops to $CHTEST_IMG/mnt/0: No such file or directory"
    [[ $output =~ $r ]]

    # destination does not exist
    run ch-run -b $IMGDIR/bind1:/goops $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/bind1 to $CHTEST_IMG/goops: No such file or directory"
    [[ $output =~ $r ]]

    # neither source nor destination exist
    run ch-run -b $IMGDIR/hoops:/goops $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/hoops to $CHTEST_IMG/goops: No such file or directory"
    [[ $output =~ $r ]]

    # correct bind followed by source does not exist
    run ch-run -b $IMGDIR/bind1:/mnt/9 -b $IMGDIR/hoops $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/hoops to $CHTEST_IMG/mnt/1: No such file or directory"
    [[ $output =~ $r ]]

    # correct bind followed by destination does not exist
    run ch-run -b $IMGDIR/bind1 -b $IMGDIR/bind2:/goops $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/bind2 to $CHTEST_IMG/goops: No such file or directory"
    [[ $output =~ $r ]]
}

@test 'broken image errors' {
    scope standard
    IMG=$BATS_TMPDIR/broken-image

    # Create an image skeleton.
    DIRS=$(echo {dev,proc,sys})
    FILES=$(echo etc/{group,hosts,passwd,resolv.conf})
    FILES_OPTIONAL=$(echo usr/bin/ch-ssh)
    mkdir -p $IMG
    for d in $DIRS; do mkdir -p $IMG/$d; done
    mkdir -p $IMG/etc $IMG/home $IMG/usr/bin $IMG/tmp
    for f in $FILES $FILES_OPTIONAL; do touch $IMG/$f; done

    # This should start up the container OK but fail to find the user command.
    run ch-run $IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ "can't execve(2): true: No such file or directory" ]]

    # For each required file, we want a correct error if it's missing.
    for f in $FILES; do
        rm $IMG/$f
        run ch-run $IMG -- true
        touch $IMG/$f  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/$f: No such file or directory"
        [[ $output =~ $r ]]
    done

    # For each optional file, we want no error if it's missing.
    for f in $FILES_OPTIONAL; do
        rm $IMG/$f
        run ch-run $IMG -- true
        touch $IMG/$f  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        [[ $output =~ "can't execve(2): true: No such file or directory" ]]
    done

    # For all files, we want a correct error if it's not a regular file.
    for f in $FILES $FILES_OPTIONAL; do
        rm $IMG/$f
        mkdir $IMG/$f
        run ch-run $IMG -- true
        rmdir $IMG/$f  # restore before test fails for idempotency
        touch $IMG/$f
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/$f: Not a directory"
        echo "expected: $r"
        [[ $output =~ $r ]]
    done

    # For each directory, we want a correct error if it's missing.
    for d in $DIRS tmp; do
        rmdir $IMG/$d
        run ch-run $IMG -- true
        mkdir $IMG/$d  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/$d: No such file or directory"
        echo "expected: $r"
        [[ $output =~ $r ]]
    done

    # For each directory, we want a correct error if it's not a directory.
    for d in $DIRS tmp; do
        rmdir $IMG/$d
        touch $IMG/$d
        run ch-run $IMG -- true
        rm $IMG/$d  # restore before test fails for idempotency
        mkdir $IMG/$d
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/$d: Not a directory"
        echo "expected: $r"
        [[ $output =~ $r ]]
    done

    # --private-tmp
    rmdir $IMG/tmp
    run ch-run --private-tmp $IMG -- true
    mkdir $IMG/tmp  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/tmp: No such file or directory"
    echo "expected: $r"
    [[ $output =~ $r ]]

    # /home without --private-home
    # FIXME: Not sure how to make the second mount(2) fail.
    rmdir $IMG/home
    run ch-run $IMG -- true
    mkdir $IMG/home  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/home: No such file or directory"
    echo "expected: $r"
    [[ $output =~ $r ]]

    # --no-home shouldn't care if /home is missing
    rmdir $IMG/home
    run ch-run --no-home $IMG -- true
    mkdir $IMG/home  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ "can't execve(2): true: No such file or directory" ]]

    # Everything should be restored and back to the original error.
    run ch-run $IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ "can't execve(2): true: No such file or directory" ]]
}

@test 'ch-run --cd' {
    scope quick
    # Default initial working directory is /.
    run ch-run $CHTEST_IMG -- pwd
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '/' ]]

    # Specify initial working directory.
    run ch-run --cd /dev $CHTEST_IMG -- pwd
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '/dev' ]]

    # Error if directory does not exist.
    run ch-run --cd /goops $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ "can't cd to /goops: No such file or directory" ]]
}

@test '/usr/bin/ch-ssh' {
    scope quick
    ls -l $CH_BIN/ch-ssh
    ch-run $CHTEST_IMG -- ls -l /usr/bin/ch-ssh
    ch-run $CHTEST_IMG -- test -x /usr/bin/ch-ssh
    host_size=$(stat -c %s $CH_BIN/ch-ssh)
    guest_size=$(ch-run $CHTEST_IMG -- stat -c %s /usr/bin/ch-ssh)
    echo "host: $host_size, guest: $guest_size"
    [[ $host_size -eq $guest_size ]]
}

@test 'relative path to image' {
    # issue #6
    scope quick
    DIRNAME=$(dirname $CHTEST_IMG)
    BASEDIR=$(basename $CHTEST_IMG)
    cd $DIRNAME && ch-run $BASEDIR -- true
}

@test 'symlink to image' {
    # issue #50
    scope quick
    ln -s $CHTEST_IMG $BATS_TMPDIR/symlink-test
    ch-run $BATS_TMPDIR/symlink-test -- true
}
