load ../common

@test 'relative path to image' {  # issue #6
    scope quick
    DIRNAME=$(dirname "$CHTEST_IMG")
    BASEDIR=$(basename "$CHTEST_IMG")
    cd "$DIRNAME" && ch-run "$BASEDIR" -- true
}

@test 'symlink to image' {  # issue #50
    scope quick
    ln -sf "$CHTEST_IMG" "$BATS_TMPDIR/symlink-test"
    ch-run "$BATS_TMPDIR/symlink-test" -- true
}

@test 'mount image read-only' {
    scope quick
    run ch-run "$CHTEST_IMG" sh <<EOF
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
    ch-run -w "$CHTEST_IMG" -- sh -c 'echo writable > write'
    ch-run -w "$CHTEST_IMG" rm write
}

@test '/usr/bin/ch-ssh' {
    scope quick
    ls -l "$CH_BIN/ch-ssh"
    ch-run "$CHTEST_IMG" -- ls -l /usr/bin/ch-ssh
    ch-run "$CHTEST_IMG" -- test -x /usr/bin/ch-ssh
    host_size=$(stat -c %s "$CH_BIN/ch-ssh")
    guest_size=$(ch-run "$CHTEST_IMG" -- stat -c %s /usr/bin/ch-ssh)
    echo "host: $host_size, guest: $guest_size"
    [[ $host_size -eq "$guest_size" ]]
}

# shellcheck disable=SC2016
@test '$HOME' {
    scope quick
    echo "host: $HOME"
    [[ $HOME ]]
    [[ $USER ]]

    # default: set $HOME
    # shellcheck disable=SC2016
    run ch-run "$CHTEST_IMG" -- /bin/sh -c 'echo $HOME'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = /home/$USER ]]

    # no change if --no-home
    # shellcheck disable=SC2016
    run ch-run --no-home "$CHTEST_IMG" -- /bin/sh -c 'echo $HOME'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "$HOME" ]]

    # puke if $HOME not set
    home_tmp=$HOME
    unset HOME
    # shellcheck disable=SC2016
    run ch-run "$CHTEST_IMG" -- /bin/sh -c 'echo $HOME'
    export HOME="$home_tmp"
    echo "$output"
    [[ $status -eq 1 ]]
    # shellcheck disable=SC2016
    [[ $output = *'cannot find home directory: $HOME not set'* ]]

    # warn if $USER not set
    user_tmp=$USER
    unset USER
    # shellcheck disable=SC2016
    run ch-run "$CHTEST_IMG" -- /bin/sh -c 'echo $HOME'
    export USER=$user_tmp
    echo "$output"
    [[ $status -eq 0 ]]
    # shellcheck disable=SC2016
    [[ $output = *'$USER not set; cannot rewrite $HOME'* ]]
    [[ $output = *"$HOME"* ]]
}

# shellcheck disable=SC2016
@test '$PATH: add /bin' {
    scope quick
    echo "$PATH"
    # if /bin is in $PATH, latter passes through unchanged
    PATH2="$CH_BIN:/bin:/usr/bin"
    echo "$PATH2"
    # shellcheck disable=SC2016
    PATH=$PATH2 run ch-run "$CHTEST_IMG" -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "$PATH2" ]]
    PATH2="/bin:$CH_BIN:/usr/bin"
    echo "$PATH2"
    # shellcheck disable=SC2016
    PATH=$PATH2 run ch-run "$CHTEST_IMG" -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "$PATH2" ]]
    # if /bin isn't in $PATH, former is added to end
    PATH2="$CH_BIN:/usr/bin"
    echo "$PATH2"
    # shellcheck disable=SC2016
    PATH=$PATH2 run ch-run "$CHTEST_IMG" -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = $PATH2:/bin ]]
}

# shellcheck disable=SC2016
@test '$PATH: unset' {
    scope standard
    BACKUP_PATH=$PATH
    unset PATH
    run "$CH_RUN_FILE" "$CHTEST_IMG" -- \
        /usr/bin/python3 -c 'import os; print(os.getenv("PATH") is None)'
    PATH=$BACKUP_PATH
    echo "$output"
    [[ $status -eq 0 ]]
    # shellcheck disable=SC2016
    [[ $output = *': $PATH not set'* ]]
    [[ $output = *'True'* ]]
}

@test 'ch-run --cd' {
    scope quick
    # Default initial working directory is /.
    run ch-run "$CHTEST_IMG" -- pwd
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '/' ]]

    # Specify initial working directory.
    run ch-run --cd /dev "$CHTEST_IMG" -- pwd
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '/dev' ]]

    # Error if directory does not exist.
    run ch-run --cd /goops "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ "can't cd to /goops: No such file or directory" ]]
}

@test 'ch-run --bind' {
    scope quick
    # one bind, default destination (/mnt/0)
    ch-run -b "$IMGDIR/bind1" "$CHTEST_IMG" -- cat /mnt/0/file1
    # one bind, explicit destination
    ch-run -b "$IMGDIR/bind1:/mnt/9" "$CHTEST_IMG" -- cat /mnt/9/file1

    # two binds, default destination
    ch-run -b "$IMGDIR/bind1" -b "$IMGDIR/bind2" "$CHTEST_IMG" \
           -- cat /mnt/0/file1 /mnt/1/file2
    # two binds, explicit destinations
    ch-run -b "$IMGDIR/bind1:/mnt/8" -b "$IMGDIR/bind2:/mnt/9" "$CHTEST_IMG" \
           -- cat /mnt/8/file1 /mnt/9/file2
    # two binds, default/explicit
    ch-run -b "$IMGDIR/bind1" -b "$IMGDIR/bind2:/mnt/9" "$CHTEST_IMG" \
           -- cat /mnt/0/file1 /mnt/9/file2
    # two binds, explicit/default
    ch-run -b "$IMGDIR/bind1:/mnt/8" -b "$IMGDIR/bind2" "$CHTEST_IMG" \
           -- cat /mnt/8/file1 /mnt/1/file2

    # bind one source at two destinations
    ch-run -b "$IMGDIR/bind1:/mnt/8" -b "$IMGDIR/bind1:/mnt/9" "$CHTEST_IMG" \
           -- diff -u /mnt/8/file1 /mnt/9/file1
    # bind two sources at one destination
    ch-run -b "$IMGDIR/bind1:/mnt/9" -b "$IMGDIR/bind2:/mnt/9" "$CHTEST_IMG" \
           -- sh -c '[ ! -e /mnt/9/file1 ] && cat /mnt/9/file2'

    # omit tmpfs at /home, which shouldn't be empty
    ch-run --no-home "$CHTEST_IMG" -- cat /home/overmount-me
    # overmount tmpfs at /home
    ch-run -b "$IMGDIR/bind1:/home" "$CHTEST_IMG" -- cat /home/file1
    # bind to /home without overmount
    ch-run --no-home -b "$IMGDIR/bind1:/home" "$CHTEST_IMG" -- cat /home/file1
    # omit default /home, with unrelated --bind
    ch-run --no-home -b "$IMGDIR/bind1" "$CHTEST_IMG" -- cat /mnt/0/file1
}

@test 'ch-run --bind errors' {
    scope quick

    # more binds (11) than default destinations
    run ch-run -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               -b "$IMGDIR/bind1" \
               "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/bind1 to $CHTEST_IMG/mnt/10: No such file or directory"
    [[ $output =~ $r ]]

    # no argument to --bind
    run ch-run "$CHTEST_IMG" -b
    echo "$output"
    [[ $status -eq 64 ]]
    [[ $output =~ 'option requires an argument' ]]

    # empty argument to --bind
    run ch-run -b '' "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--bind: no source provided' ]]

    # source not provided
    run ch-run -b :/mnt/9 "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--bind: no source provided' ]]

    # destination not provided
    run ch-run -b "$IMGDIR/bind1:" "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--bind: no destination provided' ]]

    # source does not exist
    run ch-run -b "$IMGDIR/hoops" "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/hoops to $CHTEST_IMG/mnt/0: No such file or directory"
    [[ $output =~ $r ]]

    # destination does not exist
    run ch-run -b "$IMGDIR/bind1:/goops" "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/bind1 to $CHTEST_IMG/goops: No such file or directory"
    [[ $output =~ $r ]]

    # neither source nor destination exist
    run ch-run -b "$IMGDIR/hoops:/goops" "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/hoops to $CHTEST_IMG/goops: No such file or directory"
    [[ $output =~ $r ]]

    # correct bind followed by source does not exist
    run ch-run -b "$IMGDIR/bind1:/mnt/9" -b "$IMGDIR/hoops" "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/hoops to $CHTEST_IMG/mnt/1: No such file or directory"
    [[ $output =~ $r ]]

    # correct bind followed by destination does not exist
    run ch-run -b "$IMGDIR/bind1" -b "$IMGDIR/bind2:/goops" "$CHTEST_IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't bind .+/bind2 to $CHTEST_IMG/goops: No such file or directory"
    [[ $output =~ $r ]]
}

@test 'broken image errors' {
    scope standard
    IMG="$BATS_TMPDIR/broken-image"

    # Create an image skeleton.
    DIRS=$(echo {dev,proc,sys})
    FILES=$(echo etc/{group,hosts,passwd,resolv.conf})
    # shellcheck disable=SC2116
    FILES_OPTIONAL=$(echo usr/bin/ch-ssh)
    mkdir -p "$IMG"
    for d in $DIRS; do mkdir -p "$IMG/$d"; done
    mkdir -p "$IMG/etc" "$IMG/home" "$IMG/usr/bin" "$IMG/tmp"
    for f in $FILES $FILES_OPTIONAL; do touch "$IMG/$f"; done

    # This should start up the container OK but fail to find the user command.
    run ch-run "$IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): true: No such file or directory"* ]]

    # For each required file, we want a correct error if it's missing.
    for f in $FILES; do
        rm "$IMG/$f"
        run ch-run "$IMG" -- true
        touch "$IMG/$f"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/$f: No such file or directory"
        [[ $output =~ $r ]]
    done

    # For each optional file, we want no error if it's missing.
    for f in $FILES_OPTIONAL; do
        rm "$IMG/$f"
        run ch-run "$IMG" -- true
        touch "$IMG/$f"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        [[ $output = *"can't execve(2): true: No such file or directory"* ]]
    done

    # For all files, we want a correct error if it's not a regular file.
    for f in $FILES $FILES_OPTIONAL; do
        rm "$IMG/$f"
        mkdir "$IMG/$f"
        run ch-run "$IMG" -- true
        rmdir "$IMG/$f"  # restore before test fails for idempotency
        touch "$IMG/$f"
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/$f: Not a directory"
        echo "expected: $r"
        [[ $output =~ $r ]]
    done

    # For each directory, we want a correct error if it's missing.
    for d in $DIRS tmp; do
        rmdir "$IMG/$d"
        run ch-run "$IMG" -- true
        mkdir "$IMG/$d"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/$d: No such file or directory"
        echo "expected: $r"
        [[ $output =~ $r ]]
    done

    # For each directory, we want a correct error if it's not a directory.
    for d in $DIRS tmp; do
        rmdir "$IMG/$d"
        touch "$IMG/$d"
        run ch-run "$IMG" -- true
        rm "$IMG/$d"  # restore before test fails for idempotency
        mkdir "$IMG/$d"
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/$d: Not a directory"
        echo "expected: $r"
        [[ $output =~ $r ]]
    done

    # --private-tmp
    rmdir "$IMG/tmp"
    run ch-run --private-tmp "$IMG" -- true
    mkdir "$IMG/tmp"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/tmp: No such file or directory"
    echo "expected: $r"
    [[ $output =~ $r ]]

    # /home without --private-home
    # FIXME: Not sure how to make the second mount(2) fail.
    rmdir "$IMG/home"
    run ch-run "$IMG" -- true
    mkdir "$IMG/home"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/home: No such file or directory"
    echo "expected: $r"
    [[ $output =~ $r ]]

    # --no-home shouldn't care if /home is missing
    rmdir "$IMG/home"
    run ch-run --no-home "$IMG" -- true
    mkdir "$IMG/home"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): true: No such file or directory"* ]]

    # Everything should be restored and back to the original error.
    run ch-run "$IMG" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): true: No such file or directory"* ]]
}
