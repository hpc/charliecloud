load ../common

@test 'relative path to image' {  # issue #6
    scope quick
    cd "$(dirname "$ch_timg")" && ch-run "$(basename "$ch_timg")" -- true
}

@test 'symlink to image' {  # issue #50
    scope quick
    ln -sf "$ch_timg" "${BATS_TMPDIR}/symlink-test"
    ch-run "${BATS_TMPDIR}/symlink-test" -- true
}

@test 'mount image read-only' {
    scope quick
    run ch-run "$ch_timg" sh <<EOF
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
    ch-run -w "$ch_timg" -- sh -c 'echo writable > write'
    ch-run -w "$ch_timg" rm write
}

@test '/usr/bin/ch-ssh' {
    scope quick
    ls -l "$ch_bin/ch-ssh"
    ch-run "$ch_timg" -- ls -l /usr/bin/ch-ssh
    ch-run "$ch_timg" -- test -x /usr/bin/ch-ssh
    host_size=$(stat -c %s "${ch_bin}/ch-ssh")
    guest_size=$(ch-run "$ch_timg" -- stat -c %s /usr/bin/ch-ssh)
    echo "host: ${host_size}, guest: ${guest_size}"
    [[ $host_size -eq "$guest_size" ]]
}

@test 'optional default bind mounts silently skipped' {
    scope standard

    [[ ! -e "${ch_timg}/var/opt/cray/alps/spool" ]]
    [[ ! -e "${ch_timg}/var/opt/cray/hugetlbfs" ]]

    ch-run "$ch_timg" -- mount | ( ! grep -F /var/opt/cray/alps/spool )
    ch-run "$ch_timg" -- mount | ( ! grep -F /var/opt/cray/hugetlbfs )
}

# shellcheck disable=SC2016
@test '$HOME' {
    scope quick
    echo "host: $HOME"
    [[ $HOME ]]
    [[ $USER ]]

    # default: set $HOME
    # shellcheck disable=SC2016
    run ch-run "$ch_timg" -- /bin/sh -c 'echo $HOME'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = /home/$USER ]]

    # no change if --no-home
    # shellcheck disable=SC2016
    run ch-run --no-home "$ch_timg" -- /bin/sh -c 'echo $HOME'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "$HOME" ]]

    # puke if $HOME not set
    home_tmp=$HOME
    unset HOME
    # shellcheck disable=SC2016
    run ch-run "$ch_timg" -- /bin/sh -c 'echo $HOME'
    export HOME="$home_tmp"
    echo "$output"
    [[ $status -eq 1 ]]
    # shellcheck disable=SC2016
    [[ $output = *'cannot find home directory: $HOME not set'* ]]

    # warn if $USER not set
    user_tmp=$USER
    unset USER
    # shellcheck disable=SC2016
    run ch-run "$ch_timg" -- /bin/sh -c 'echo $HOME'
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
    PATH2="$ch_bin:/bin:/usr/bin"
    echo "$PATH2"
    # shellcheck disable=SC2016
    PATH=$PATH2 run ch-run "$ch_timg" -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "$PATH2" ]]
    PATH2="/bin:$ch_bin:/usr/bin"
    echo "$PATH2"
    # shellcheck disable=SC2016
    PATH=$PATH2 run ch-run "$ch_timg" -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "$PATH2" ]]
    # if /bin isn't in $PATH, former is added to end
    PATH2="$ch_bin:/usr/bin"
    echo "$PATH2"
    # shellcheck disable=SC2016
    PATH=$PATH2 run ch-run "$ch_timg" -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = $PATH2:/bin ]]
}

# shellcheck disable=SC2016
@test '$PATH: unset' {
    scope standard
    old_path=$PATH
    unset PATH
    run "$ch_runfile" "$ch_timg" -- \
        /usr/bin/python3 -c 'import os; print(os.getenv("PATH") is None)'
    PATH=$old_path
    echo "$output"
    [[ $status -eq 0 ]]
    # shellcheck disable=SC2016
    [[ $output = *': $PATH not set'* ]]
    [[ $output = *'True'* ]]
}

@test 'ch-run --cd' {
    scope quick
    # Default initial working directory is /.
    run ch-run "$ch_timg" -- pwd
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '/' ]]

    # Specify initial working directory.
    run ch-run --cd /dev "$ch_timg" -- pwd
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '/dev' ]]

    # Error if directory does not exist.
    run ch-run --cd /goops "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ "can't cd to /goops: No such file or directory" ]]
}

@test 'ch-run --bind' {
    scope quick
    # one bind, default destination (/mnt/0)
    ch-run -b "${ch_imgdir}/bind1" "$ch_timg" -- cat /mnt/0/file1
    # one bind, explicit destination
    ch-run -b "${ch_imgdir}/bind1:/mnt/9" "$ch_timg" -- cat /mnt/9/file1

    # two binds, default destination
    ch-run -b "${ch_imgdir}/bind1" -b "${ch_imgdir}/bind2" "$ch_timg" \
           -- cat /mnt/0/file1 /mnt/1/file2
    # two binds, explicit destinations
    ch-run -b "${ch_imgdir}/bind1:/mnt/8" -b "${ch_imgdir}/bind2:/mnt/9" \
           "$ch_timg" \
           -- cat /mnt/8/file1 /mnt/9/file2
    # two binds, default/explicit
    ch-run -b "${ch_imgdir}/bind1" -b "${ch_imgdir}/bind2:/mnt/9" "$ch_timg" \
           -- cat /mnt/0/file1 /mnt/9/file2
    # two binds, explicit/default
    ch-run -b "${ch_imgdir}/bind1:/mnt/8" -b "${ch_imgdir}/bind2" "$ch_timg" \
           -- cat /mnt/8/file1 /mnt/1/file2

    # bind one source at two destinations
    ch-run -b "${ch_imgdir}/bind1:/mnt/8" -b "${ch_imgdir}/bind1:/mnt/9" \
           "$ch_timg" \
           -- diff -u /mnt/8/file1 /mnt/9/file1
    # bind two sources at one destination
    ch-run -b "${ch_imgdir}/bind1:/mnt/9" -b "${ch_imgdir}/bind2:/mnt/9" \
           "$ch_timg" \
           -- sh -c '[ ! -e /mnt/9/file1 ] && cat /mnt/9/file2'

    # omit tmpfs at /home, which shouldn't be empty
    ch-run --no-home "$ch_timg" -- cat /home/overmount-me
    # overmount tmpfs at /home
    ch-run -b "${ch_imgdir}/bind1:/home" "$ch_timg" -- cat /home/file1
    # bind to /home without overmount
    ch-run --no-home -b "${ch_imgdir}/bind1:/home" "$ch_timg" -- cat /home/file1
    # omit default /home, with unrelated --bind
    ch-run --no-home -b "${ch_imgdir}/bind1" "$ch_timg" -- cat /mnt/0/file1
}

@test 'ch-run --bind errors' {
    scope quick

    # more binds (11) than default destinations
    run ch-run -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               -b "${ch_imgdir}/bind1" \
               "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_timg}/mnt/10"* ]]

    # no argument to --bind
    run ch-run "$ch_timg" -b
    echo "$output"
    [[ $status -eq 64 ]]
    [[ $output = *'option requires an argument'* ]]

    # empty argument to --bind
    run ch-run -b '' "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--bind: no source provided'* ]]

    # source not provided
    run ch-run -b :/mnt/9 "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--bind: no source provided'* ]]

    # destination not provided
    run ch-run -b "${ch_imgdir}/bind1:" "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--bind: no destination provided'* ]]

    # source does not exist
    run ch-run -b "${ch_imgdir}/hoops" "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_imgdir}/hoops"* ]]

    # destination does not exist
    run ch-run -b "${ch_imgdir}/bind1:/goops" "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_timg}/goops"* ]]

    # neither source nor destination exist
    run ch-run -b "${ch_imgdir}/hoops:/goops" "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_imgdir}/hoops"* ]]

    # correct bind followed by source does not exist
    run ch-run -b "${ch_imgdir}/bind1" -b "${ch_imgdir}/hoops" "$ch_timg" -- \
              true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_imgdir}/hoops"* ]]

    # correct bind followed by destination does not exist
    run ch-run -b "${ch_imgdir}/bind1" -b "${ch_imgdir}/bind2:/goops" \
               "$ch_timg" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_timg}/goops"* ]]
}

@test 'broken image errors' {
    scope standard
    img="${BATS_TMPDIR}/broken-image"

    # Create an image skeleton.
    dirs=$(echo {dev,proc,sys})
    files=$(echo etc/{group,hosts,passwd,resolv.conf})
    # shellcheck disable=SC2116
    files_optional=$(echo usr/bin/ch-ssh)
    mkdir -p "$img"
    for d in $dirs; do mkdir -p "${img}/$d"; done
    mkdir -p "${img}/etc" "${img}/home" "${img}/usr/bin" "${img}/tmp"
    for f in $files $files_optional; do touch "${img}/${f}"; done

    # This should start up the container OK but fail to find the user command.
    run ch-run "$img" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): true: No such file or directory"* ]]

    # For each required file, we want a correct error if it's missing.
    for f in $files; do
        echo "required: ${f}"
        rm "${img}/${f}"
        ls -l "${img}/${f}" || true
        run ch-run "$img" -- true
        touch "${img}/${f}"  # restore before test fails for idempotency
        echo "$output"
        echo "$output" >> ruff
        [[ $status -eq 1 ]]
        [[ $output =~ .*"can't bind: not found: "[/a-zA-Z._0-9-]*$f.* ]]
    done

    # For each optional file, we want no error if it's missing.
    for f in $files_optional; do
        echo "optional: ${f}"
        rm "${img}/${f}"
        run ch-run "$img" -- true
        touch "${img}/${f}"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        [[ $output = *"can't execve(2): true: No such file or directory"* ]]
    done

    # For all files, we want a correct error if it's not a regular file.
    for f in $files $files_optional; do
        echo "not a regular file: ${f}"
        rm "${img}/${f}"
        mkdir "${img}/${f}"
        run ch-run "$img" -- true
        rmdir "${img}/${f}"  # restore before test fails for idempotency
        touch "${img}/${f}"
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/${f}: Not a directory"
        echo "expected: ${r}"
        [[ $output =~ $r ]]
    done

    # For each directory, we want a correct error if it's missing.
    for d in $dirs tmp; do
        echo "required: ${d}"
        rmdir "${img}/${d}"
        run ch-run "$img" -- true
        mkdir "${img}/${d}"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        [[ $output =~ .*"can't bind: not found: "[/a-zA-Z._0-9-]*$d.* ]]
    done

    # For each directory, we want a correct error if it's not a directory.
    for d in $dirs tmp; do
        echo "not a directory: ${d}"
        rmdir "${img}/${d}"
        touch "${img}/${d}"
        run ch-run "$img" -- true
        rm "${img}/${d}"    # restore before test fails for idempotency
        mkdir "${img}/${d}"
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/${d}: Not a directory"
        echo "expected: ${r}"
        [[ $output =~ $r ]]
    done

    # --private-tmp
    rmdir "${img}/tmp"
    run ch-run --private-tmp "$img" -- true
    mkdir "${img}/tmp"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/tmp: No such file or directory"
    echo "expected: ${r}"
    [[ $output =~ $r ]]

    # /home without --private-home
    # FIXME: Not sure how to make the second mount(2) fail.
    rmdir "${img}/home"
    run ch-run "$img" -- true
    mkdir "${img}/home"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/home: No such file or directory"
    echo "expected: ${r}"
    [[ $output =~ $r ]]

    # --no-home shouldn't care if /home is missing
    rmdir "${img}/home"
    run ch-run --no-home "$img" -- true
    mkdir "${img}/home"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): true: No such file or directory"* ]]

    # Everything should be restored and back to the original error.
    run ch-run "$img" -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): true: No such file or directory"* ]]
}
