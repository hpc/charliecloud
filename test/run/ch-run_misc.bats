load ../common


@test 'relative path to image' {  # issue #6
    scope full
    cd "$(dirname "$ch_timg")" && ch-run "$(basename "$ch_timg")" -- /bin/true
}


@test 'symlink to image' {  # issue #50
    scope full
    ln -sf "$ch_timg" "${BATS_TMPDIR}/symlink-test"
    ch-run "${BATS_TMPDIR}/symlink-test" -- /bin/true
}


@test 'mount image read-only' {
    scope standard
    run ch-run "$ch_timg" sh <<EOF
set -e
dd if=/dev/zero bs=1 count=1 of=/out
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output =~ 'Read-only file system' ]]
}


@test 'mount image read-write' {
    scope standard
    [[ $CH_TEST_PACK_FMT = *-unpack ]] || skip 'needs writeable image'
    ch-run -w "$ch_timg" -- sh -c 'echo writable > write'
    ch-run -w "$ch_timg" rm write
}


@test 'optional default bind mounts silently skipped' {
    scope standard

    [[ ! -e "${ch_timg}/var/opt/cray/alps/spool" ]]
    [[ ! -e "${ch_timg}/var/opt/cray/hugetlbfs" ]]

    ch-run "$ch_timg" -- mount | ( ! grep -F /var/opt/cray/alps/spool )
    ch-run "$ch_timg" -- mount | ( ! grep -F /var/opt/cray/hugetlbfs )
}


@test "\$CH_RUNNING" {
    scope standard

    if [[ -v CH_RUNNING ]]; then
      echo "\$CH_RUNNING already set: $CH_RUNNING"
      false
    fi

    run ch-run "$ch_timg" -- /bin/sh -c 'env | grep -E ^CH_RUNNING'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'CH_RUNNING=Weird Al Yankovic' ]]
}

@test "\$HOME" {
    scope quick
    echo "host: $HOME"
    [[ $HOME ]]
    [[ $USER ]]

    # default: no change
    # shellcheck disable=SC2016
    run ch-run "$ch_timg" -- /bin/sh -c 'echo $HOME'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "$HOME" ]]

    # set $HOME if --home
    # shellcheck disable=SC2016
    run ch-run --home "$ch_timg" -- /bin/sh -c 'echo $HOME'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = /home/$USER ]]

    # puke if $HOME not set
    home_tmp=$HOME
    unset HOME
    # shellcheck disable=SC2016
    run ch-run --home "$ch_timg" -- /bin/sh -c 'echo $HOME'
    export HOME="$home_tmp"
    echo "$output"
    [[ $status -eq 1 ]]
    # shellcheck disable=SC2016
    [[ $output = *'--home failed: $HOME not set'* ]]

    # puke if $USER not set
    user_tmp=$USER
    unset USER
    # shellcheck disable=SC2016
    run ch-run --home "$ch_timg" -- /bin/sh -c 'echo $HOME'
    export USER=$user_tmp
    echo "$output"
    [[ $status -eq 1 ]]
    # shellcheck disable=SC2016
    [[ $output = *'$USER not set'* ]]
}


@test "\$PATH: add /bin" {
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
    # if /bin isn’t in $PATH, former is added to end
    PATH2="$ch_bin:/usr/bin"
    echo "$PATH2"
    # shellcheck disable=SC2016
    PATH=$PATH2 run ch-run "$ch_timg" -- /bin/sh -c 'echo $PATH'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = $PATH2:/bin ]]
}


@test "\$PATH: unset" {
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


@test "\$TMPDIR" {
    scope standard
    mkdir -p "${BATS_TMPDIR}/tmpdir"
    touch "${BATS_TMPDIR}/tmpdir/file-in-tmpdir"
    TMPDIR=${BATS_TMPDIR}/tmpdir run ch-run "$ch_timg" -- ls -1 /tmp
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = file-in-tmpdir ]]
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
    run ch-run --cd /goops "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ "can't cd to /goops: No such file or directory" ]]
}


@test 'ch-run --bind' {
    scope quick
    [[ $CH_TEST_PACK_FMT = *-unpack ]] || skip 'needs writeable image'

    # set up sources
    mkdir -p "${ch_timg}/${ch_imgdir}/bind1"
    mkdir -p "${ch_timg}/${ch_imgdir}/bind2"
    # remove destinations that will be created
    rmdir "${ch_timg}/bind3" || true
    [[ ! -e ${ch_timg}/bind3 ]]
    rmdir "${ch_timg}/bind4/a" "${ch_timg}/bind4/b" "${ch_timg}/bind4" || true
    [[ ! -e ${ch_timg}/bind4 ]]

    # one bind, default destination
    ch-run -b "${ch_imgdir}/bind1" "$ch_timg" -- cat "${ch_imgdir}/bind1/file1"
    # one bind, explicit destination
    ch-run -b "${ch_imgdir}/bind1:/mnt/9" "$ch_timg" -- cat /mnt/9/file1

    # one bind, create destination, one level
    ch-run -w -b "${ch_imgdir}/bind1:/bind3" "$ch_timg" -- cat /bind3/file1
    # one bind, create destination, two levels
    ch-run -w -b "${ch_imgdir}/bind1:/bind4/a" "$ch_timg" -- cat /bind4/a/file1
    # one bind, create destination, two levels via symlink
    [[ -L ${ch_timg}/mnt/bind4 ]]
    ch-run -w -b "${ch_imgdir}/bind1:/mnt/bind4/b" "$ch_timg" \
           -- cat /bind4/b/file1

    # two binds, default destination
    ch-run -b "${ch_imgdir}/bind1" -b "${ch_imgdir}/bind2" "$ch_timg" \
           -- cat "${ch_imgdir}/bind1/file1" "${ch_imgdir}/bind2/file2"
    # two binds, explicit destinations
    ch-run -b "${ch_imgdir}/bind1:/mnt/8" -b "${ch_imgdir}/bind2:/mnt/9" \
           "$ch_timg" \
           -- cat /mnt/8/file1 /mnt/9/file2
    # two binds, default/explicit
    ch-run -b "${ch_imgdir}/bind1" -b "${ch_imgdir}/bind2:/mnt/9" "$ch_timg" \
           -- cat "${ch_imgdir}/bind1/file1" /mnt/9/file2
    # two binds, explicit/default
    ch-run -b "${ch_imgdir}/bind1:/mnt/8" -b "${ch_imgdir}/bind2" "$ch_timg" \
           -- cat /mnt/8/file1 "${ch_imgdir}/bind2/file2"

    # bind one source at two destinations
    ch-run -b "${ch_imgdir}/bind1:/mnt/8" -b "${ch_imgdir}/bind1:/mnt/9" \
           "$ch_timg" \
           -- diff -u /mnt/8/file1 /mnt/9/file1
    # bind two sources at one destination
    ch-run -b "${ch_imgdir}/bind1:/mnt/9" -b "${ch_imgdir}/bind2:/mnt/9" \
           "$ch_timg" \
           -- sh -c '[ ! -e /mnt/9/file1 ] && cat /mnt/9/file2'

    # omit tmpfs at /home, which shouldn’t be empty
    ch-run "$ch_timg" -- cat /home/overmount-me
    # bind to /home without overmount
    ch-run -b "${ch_imgdir}/bind1:/home" "$ch_timg" -- cat /home/file1
    # overmount tmpfs at /home
    ch-run --home -b "${ch_imgdir}/bind1:/home" "$ch_timg" -- cat /home/file1
}


@test 'ch-run --bind errors' {
    scope quick
    [[ $CH_TEST_PACK_FMT = *-unpack ]] || skip 'needs writeable image'

    # no argument to --bind
    run ch-run "$ch_timg" -b
    echo "$output"
    [[ $status -eq 64 ]]
    [[ $output = *'option requires an argument'* ]]

    # empty argument to --bind
    run ch-run -b '' "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--bind: no source provided'* ]]

    # source not provided
    run ch-run -b :/mnt/9 "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--bind: no source provided'* ]]

    # destination not provided
    run ch-run -b "${ch_imgdir}/bind1:" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--bind: no destination provided'* ]]

    # destination is /
    run ch-run -b "${ch_imgdir}/bind1:/" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"--bind: destination can't be /"* ]]

    # destination is relative
    run ch-run -b "${ch_imgdir}/bind1:foo" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"--bind: destination must be absolute"* ]]

    # destination climbs out of image, exists
    run ch-run -b "${ch_imgdir}/bind1:/.." "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: ${ch_imgdir} not subdirectory of ${ch_timg}"* ]]

    # destination climbs out of image, does not exist
    run ch-run -b "${ch_imgdir}/bind1:/../doesnotexist/a" "$ch_timg" \
               -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: ${ch_imgdir}/doesnotexist not subdirectory of ${ch_timg}"* ]]
    [[ ! -e ${ch_imgdir}/doesnotexist ]]

    # source does not exist
    run ch-run -b "${ch_imgdir}/hoops" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: source not found: ${ch_imgdir}/hoops"* ]]

    # destination does not exist
    run ch-run -b "${ch_imgdir}/bind1:/goops" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: ${ch_timg}/goops: Read-only file system"* ]]

    # neither source nor destination exist
    run ch-run -b "${ch_imgdir}/hoops:/goops" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: source not found: ${ch_imgdir}/hoops"* ]]

    # correct bind followed by source does not exist
    run ch-run -b "${ch_imgdir}/bind1:/mnt/0" -b "${ch_imgdir}/hoops" \
               "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: source not found: ${ch_imgdir}/hoops"* ]]

    # correct bind followed by destination does not exist
    run ch-run -b "${ch_imgdir}/bind1:/mnt/0" -b "${ch_imgdir}/bind2:/goops" \
               "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: ${ch_timg}/goops: Read-only file system"* ]]

    # destination is broken symlink, absolute
    run ch-run -b "${ch_imgdir}/bind1:/mnt/link-b0rken-abs" "$ch_timg" \
        -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: symlink not relative: ${ch_timg}/mnt/link-b0rken-abs"* ]]

    # destination is broken symlink, relative, directly
    run ch-run -b "${ch_imgdir}/bind1:/mnt/link-b0rken-rel" "$ch_timg" \
        -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: broken symlink: ${ch_timg}/mnt/link-b0rken-rel"* ]]
    [[ ! -e ${ch_timg}/mnt/doesnotexist ]]

    # destination goes through broken symlink
    run ch-run -b "${ch_imgdir}/bind1:/mnt/link-b0rken-rel/a" "$ch_timg" \
               -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: broken symlink: ${ch_timg}/mnt/link-b0rken-rel"* ]]
    [[ ! -e ${ch_timg}/mnt/doesnotexist ]]

    # destination is absolute symlink outside image
    run ch-run -b "${ch_imgdir}/bind1:/mnt/link-bad-abs" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: "*" not subdirectory of ${ch_timg}"* ]]

    # destination relative symlink outside image
    run ch-run -b "${ch_imgdir}/bind1:/mnt/link-bad-rel" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: "*" not subdirectory of ${ch_timg}"* ]]

    # mkdir(2) under existing bind-mount, default, first level
    run ch-run -b "${ch_imgdir}/bind1:/proc/doesnotexist" "$ch_timg" \
        -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: ${ch_timg}/proc/doesnotexist under existing bind-mount ${ch_timg}/proc "* ]]

    # mkdir(2) under existing bind-mount, user-supplied, first level
    run ch-run -b "${ch_imgdir}/bind1:/mnt/0" \
               -b "${ch_imgdir}/bind2:/mnt/0/foo" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: ${ch_timg}/mnt/0/foo under existing bind-mount ${ch_timg}/mnt/0 "* ]]

    # mkdir(2) under existing bind-mount, default, 2nd level
    run ch-run -b "${ch_imgdir}/bind1:/proc/sys/doesnotexist" "$ch_timg" \
        -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't mkdir: ${ch_timg}/proc/sys/doesnotexist under existing bind-mount ${ch_timg}/proc "* ]]
}


@test 'ch-run --set-env' {
    scope standard

    # Quirk that is probably too obscure to put in the documentation: The
    # string containing only two straight quotes does not round-trip through
    # “printenv” or “env”, though it does round-trip through Bash “set”:
    #
    #   $ export foo="''"
    #   $ echo [$foo]
    #   ['']
    #   $ set | fgrep foo
    #   foo=''\'''\'''
    #   $ eval $(set | fgrep foo)
    #   $ echo [$foo]
    #   ['']
    #   $ printenv | fgrep foo
    #   foo=''
    #   $ eval $(printenv | fgrep foo)
    #   $ echo $foo
    #   []

    # Valid inputs. Use Python to print the results to avoid ambiguity.
    export SET=foo
    export SET2=boo
    f_in=${BATS_TMPDIR}/env.txt
    cat <<'EOF' > "$f_in"
chse_a1=bar
chse_a2=bar=baz
chse_a3=bar baz
chse_a4='bar'
chse_a5=
chse_a6=''
chse_a7=''''

chse_b1="bar"
chse_b2=bar # baz
 chse_b3=bar
chse_b4= bar

chse_c1=foo
chse_c1=bar

chse_d1=foo:
chse_d2=:foo
chse_d3=:
chse_d4=::
chse_d5=$SET
chse_d6=$SET:$SET2
chse_d7=bar:$SET
chse_d8=bar:baz:$SET
chse_d9=$SET:bar
chse_dA=$SET:bar:baz
chse_dB=bar:$SET:baz
chse_dC=bar:baz:$SET:bar:baz

chse_e1=:$SET
chse_e2=::$SET
chse_e3=$SET:
chse_e4=$SET::
chse_e5=bar:$
chse_e6=bar:*
chse_e7=bar$SET
chse_e8=bar::$SET

chse_f1=$UNSET
chse_f2=foo:$UNSET
chse_f3=foo:$UNSET:
chse_f4=$UNSET:foo
chse_f5=:$UNSET:foo
chse_f6=foo:$UNSET:$UNSET2
chse_f7=foo:$UNSET:$UNSET2:
chse_f8=$UNSET:$UNSET2:foo
chse_f9=:$UNSET:$UNSET2:foo
chse_fA=foo:$UNSET:bar
chse_fB=foo:$UNSET:$UNSET2:bar
chse_fC=:$UNSET
chse_fD=::$UNSET
chse_fE=$UNSET:
chse_fF=$UNSET::

EOF
    cat "$f_in"
    output_expected=$(cat <<'EOF'
(' chse_b3', 'bar')
('chse_a1', 'bar')
('chse_a2', 'bar=baz')
('chse_a3', 'bar baz')
('chse_a4', 'bar')
('chse_a5', '')
('chse_a6', '')
('chse_a7', "''")
('chse_b1', '"bar"')
('chse_b2', 'bar # baz')
('chse_b4', ' bar')
('chse_c1', 'bar')
('chse_d1', 'foo:')
('chse_d2', ':foo')
('chse_d3', ':')
('chse_d4', '::')
('chse_d5', 'foo')
('chse_d6', 'foo:boo')
('chse_d7', 'bar:foo')
('chse_d8', 'bar:baz:foo')
('chse_d9', 'foo:bar')
('chse_dA', 'foo:bar:baz')
('chse_dB', 'bar:foo:baz')
('chse_dC', 'bar:baz:foo:bar:baz')
('chse_e1', ':foo')
('chse_e2', '::foo')
('chse_e3', 'foo:')
('chse_e4', 'foo::')
('chse_e5', 'bar:$')
('chse_e6', 'bar:*')
('chse_e7', 'bar$SET')
('chse_e8', 'bar::foo')
('chse_f1', '')
('chse_f2', 'foo')
('chse_f3', 'foo:')
('chse_f4', 'foo')
('chse_f5', ':foo')
('chse_f6', 'foo')
('chse_f7', 'foo:')
('chse_f8', 'foo')
('chse_f9', ':foo')
('chse_fA', 'foo:bar')
('chse_fB', 'foo:bar')
('chse_fC', '')
('chse_fD', ':')
('chse_fE', '')
('chse_fF', ':')
EOF
)
    run ch-run --set-env="$f_in" "$ch_timg" -- python3 -c 'import os; [print((k,v)) for (k,v) in sorted(os.environ.items()) if "chse_" in k]'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")
}


@test 'ch-run --set-env0' {
    scope standard

    export SET=foo
    f_in=${BATS_TMPDIR}/env.bin
    {
        printf 'chse_a1=bar\0'
        printf "chse_a4='bar'\0"
        #shellcheck disable=SC2016
        printf 'chse_d7=bar:$SET\0'
        printf 'chse_g1=foo\nbar\0'
    } > "$f_in"
    hd "$f_in" | sed -E 's/^0000//'  # trim a few zeros to make it fit

    output_expected=$(cat <<'EOF'
('chse_a1', 'bar')
('chse_a4', 'bar')
('chse_d7', 'bar:foo')
('chse_g1', 'foo\nbar')
EOF
)
    run ch-run --set-env0="$f_in" "$ch_timg" -- python3 -c 'import os; [print((k,v)) for (k,v) in sorted(os.environ.items()) if "chse_" in k]'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")
}


@test 'ch-run --set-env from Dockerfile' {
    scope standard
    prerequisites_ok argenv
    img=${ch_imgdir}/argenv

    output_expected=$(cat <<'EOF'
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)

    run ch-run --set-env "$img" -- sh -c 'env | grep -E "^chse_"'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")
}


@test 'ch-run --set-env errors' {
    scope standard
    f_in=${BATS_TMPDIR}/env.txt

    # file does not exist
    run ch-run --set-env=doesnotexist.txt "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't open: doesnotexist.txt: No such file or directory"* ]]

    # /ch/environment missing
    run ch-run --set-env "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't open: /ch/environment: No such file or directory"* ]]

    # Note: I’m not sure how to test an error during reading, i.e., getline(3)
    # rather than fopen(3). Hence no test for “error reading”.

    # invalid line: missing “=”
    echo 'FOO bar' > "$f_in"
    run ch-run --set-env="$f_in" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't parse variable: no delimiter: ${f_in}:1"* ]]

    # invalid line: no name
    echo '=bar' > "$f_in"
    run ch-run --set-env="$f_in" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't parse variable: empty name: ${f_in}:1"* ]]
}


# shellcheck disable=SC2016
@test 'ch-run --set-env command line' {
    scope standard

    # missing “'”
    # shellcheck disable=SC2086
    run ch-run --set-env=foo='$test:app' --env-no-expand -v "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'environment: foo=$test:app'* ]]

    # missing environment variable
    run ch-run --set-env='$PATH:foo' "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'$PATH:foo: No such file or directory'* ]]
}


@test 'ch-run --unset-env' {
    scope standard

    export chue_1=foo
    export chue_2=bar

    printf '\n# Nothing\n\n'
    run ch-run --unset-env=doesnotmatch "$ch_timg" -- env
    echo "$output" | sort
    [[ $status -eq 0 ]]
    ex='^(_|CH_RUNNING|HOME|PATH|SHLVL|TMPDIR)='  # expected to change
    diff -u <(env | grep -Ev "$ex" | sort) \
            <(echo "$output" | grep -Ev "$ex" | sort)

    printf '\n# Everything\n\n'
    run ch-run --unset-env='*' "$ch_timg" -- env
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'CH_RUNNING=Weird Al Yankovic' ]]

    printf '\n# Everything, plus shell re-adds\n\n'
    run ch-run --unset-env='*' "$ch_timg" -- /bin/sh -c 'env | sort'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(printf 'CH_RUNNING=Weird Al Yankovic\nPWD=/\nSHLVL=1\n') \
            <(echo "$output")

    printf '\n# Without wildcards\n\n'
    run ch-run --unset-env=chue_1 "$ch_timg" -- env
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(printf 'chue_2=bar\n') <(echo "$output" | grep -E '^chue_')

    printf '\n# With wildcards\n\n'
    run ch-run --unset-env='chue_*' "$ch_timg" -- env
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -E '^chue_') = '' ]]

    printf '\n# Empty string\n\n'
    run ch-run --unset-env= "$ch_timg" -- env
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--unset-env: GLOB must have non-zero length'* ]]
}


@test 'ch-run --unset-env extglobs' {
    scope standard
    ch-run --feature extglob || skip 'extended globs not available'

    export chue_1=foo
    export chue_2=bar

    printf '\n# With extended globs to select\n\n'
    run ch-run --unset-env='chue_@(1|2)' "$ch_timg" -- env
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -E '^chue_') = '' ]]

    printf '\n# With extended globs to deselect\n\n'
    run ch-run --unset-env='!(chue_*)' "$ch_timg" -- env
    echo "$output"
    [[ $status -eq 0 ]]
    output_expected=$(cat <<'EOF'
CH_RUNNING=Weird Al Yankovic
chue_1=foo
chue_2=bar
EOF
)
    diff -u <(echo "$output_expected") <(echo "$output" | LC_ALL=C sort)
}


@test 'ch-run mixed --set-env and --unset-env' {
    scope standard

    # Input.
    export chmix_a1=z
    export chmix_a2=y
    export chmix_a3=x
    f1_in=${BATS_TMPDIR}/env1.txt
    cat <<'EOF' > "$f1_in"
chmix_b1=w
chmix_b2=v
EOF
    f2_in=${BATS_TMPDIR}/env2.txt
    cat <<'EOF' > "$f2_in"
chmix_c1=u
chmix_c2=t
EOF

    # unset, unset
    output_expected=$(cat <<'EOF'
chmix_a3=x
EOF
)
    run ch-run --unset-env=chmix_a1 --unset-env=chmix_a2 "$ch_timg" -- \
               sh -c 'env | grep -E ^chmix_ | sort'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")

    echo '# set, set'
    output_expected=$(cat <<'EOF'
chmix_a1=z
chmix_a2=y
chmix_a3=x
chmix_b1=w
chmix_b2=v
chmix_c1=u
chmix_c2=t
EOF
)
    run ch-run --set-env="$f1_in" --set-env="$f2_in" "$ch_timg" -- \
               sh -c 'env | grep -E ^chmix_ | sort'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")

    echo '# unset, set'
    output_expected=$(cat <<'EOF'
chmix_a2=y
chmix_a3=x
chmix_b1=w
chmix_b2=v
EOF
)
    run ch-run --unset-env=chmix_a1 --set-env="$f1_in" "$ch_timg" -- \
               sh -c 'env | grep -E ^chmix_ | sort'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")

    echo '# set, unset'
    output_expected=$(cat <<'EOF'
chmix_a1=z
chmix_a2=y
chmix_a3=x
chmix_b1=w
EOF
)
    run ch-run  --set-env="$f1_in" --unset-env=chmix_b2 "$ch_timg" -- \
               sh -c 'env | grep -E ^chmix_ | sort'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")

    echo '# unset, set, unset'
    output_expected=$(cat <<'EOF'
chmix_a2=y
chmix_a3=x
chmix_b1=w
EOF
)
    run ch-run --unset-env=chmix_a1 \
               --set-env="$f1_in" \
               --unset-env=chmix_b2 \
               "$ch_timg" -- sh -c 'env | grep -E ^chmix_ | sort'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")

    echo '# set, unset, set'
    output_expected=$(cat <<'EOF'
chmix_a1=z
chmix_a2=y
chmix_a3=x
chmix_b1=w
chmix_c1=u
chmix_c2=t
EOF
)
    run ch-run --set-env="$f1_in" \
               --unset-env=chmix_b2 \
               --set-env="$f2_in" \
               "$ch_timg" -- sh -c 'env | grep -E ^chmix_ | sort'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")
}

@test 'ch-run: internal SquashFUSE mounting' {
    scope standard
    [[ $CH_TEST_PACK_FMT == squash-mount ]] || skip 'squash-mount format only'

    ch_mnt="/var/tmp/${USER}.ch/mnt"

    # default mount point
    run ch-run -v "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: (null)"* ]]
    [[ $output = *"using default mount point: ${ch_mnt}"* ]]
    [[ -d ${ch_mnt} ]]
    rmdir "${ch_mnt}"

    # -m option
    mountpt="${BATS_TMPDIR}/sqfs_tmpdir"
    mountpt_real=$(realpath "$mountpt")
    [[ -e $mountpt ]] || mkdir "$mountpt"
    run ch-run -m "$mountpt" -v "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: ${mountpt_real}"* ]]
    rmdir "$mountpt"

    # -m with non-sqfs img
    img=$(realpath "${BATS_TMPDIR}/dirimg")
    ch-convert -i squash "$ch_timg" "$img"
    run ch-run -m /doesnotexist -v "$img" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"warning: --mount invalid with directory image, ignoring"* ]]
    [[ $output = *"newroot: ${img}"* ]]
    rm -Rf --one-file-system "$img"
}

@test 'ch-run: internal SquashFUSE errors' {
    scope standard
    [[ $CH_TEST_PACK_FMT == squash-mount ]] || skip 'squash-mount format only'

    # mount point is empty string
    run ch-run --mount= "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]  # exits with status of 139
    [[ $output = *"mount point can't be empty string"* ]]

    # mount point doesn’t exist
    run ch-run -m /doesnotexist "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]  # exits with status of 139
    [[ $output = *"can't stat mount point: /doesnotexist: No such file or directory"* ]]

    # mount point is a file
    run ch-run -m ./fixtures/README "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory: '*'/fixtures/README'* ]]

    # image is file but not sqfs
    run ch-run -vv ./fixtures/README -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'magic expected: 6873 7173; actual: 596f 7520'* ]]
    [[ $output = *'unknown image type: '*'/fixtures/README'* ]]

    # image is a broken sqfs
    sq_tmp="$BATS_TMPDIR"/b0rken.sqfs
    cp "$ch_timg" "$sq_tmp"
    # corrupt inode count (bytes 4–7, 0-indexed)
    printf '\xED\x5F\x84\x00' | dd of="$sq_tmp" bs=1 count=4 seek=4 conv=notrunc
    ls -l "$ch_timg" "$sq_tmp"
    run ch-run -vv "$sq_tmp" -- ls -l /
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'magic expected: 6873 7173; actual: 6873 7173'* ]]
    [[ $output = *"can't open SquashFS: ${sq_tmp}"* ]]
    rm "$sq_tmp"
}

@test 'broken image errors' {
    scope standard
    img=${BATS_TMPDIR}/broken-image
    tmpdir=${TMPDIR:-/tmp}

    # Create an image skeleton.
    dirs=$(echo {dev,proc,sys})
    files=$(echo etc/{group,passwd})
    files_optional=$(echo etc/{hosts,resolv.conf})
    mkdir -p "$img"
    for d in $dirs; do mkdir -p "${img}/$d"; done
    mkdir -p "${img}/etc" "${img}/home" "${img}/usr/bin" "${img}/tmp"
    for f in $files $files_optional; do touch "${img}/${f}"; done

    # This should start up the container OK but fail to find the user command.
    run ch-run "$img" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): /bin/true: No such file or directory"* ]]

    # For each required file, we want a correct error if it’s missing.
    for f in $files; do
        echo "required: ${f}"
        rm "${img}/${f}"
        ls -l "${img}/${f}" || true
        run ch-run "$img" -- /bin/true
        touch "${img}/${f}"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind: destination not found: .+/${f}"
        echo "expected: ${r}"
        [[ $output =~ $r ]]
    done

    # For each optional file, we want no error if it’s missing.
    for f in $files_optional; do
        echo "optional: ${f}"
        rm "${img}/${f}"
        run ch-run "$img" -- /bin/true
        touch "${img}/${f}"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        [[ $output = *"can't execve(2): /bin/true: No such file or directory"* ]]
    done

    # For all files, we want a correct error if it’s not a regular file.
    for f in $files $files_optional; do
        echo "not a regular file: ${f}"
        rm "${img}/${f}"
        mkdir "${img}/${f}"
        run ch-run "$img" -- /bin/true
        rmdir "${img}/${f}"  # restore before test fails for idempotency
        touch "${img}/${f}"
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind .+ to /.+/${f}: Not a directory"
        echo "expected: ${r}"
        [[ $output =~ $r ]]
    done

    # For each directory, we want a correct error if it’s missing.
    for d in $dirs tmp; do
        echo "required: ${d}"
        rmdir "${img}/${d}"
        run ch-run "$img" -- /bin/true
        mkdir "${img}/${d}"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        r="can't bind: destination not found: .+/${d}"
        echo "expected: ${r}"
        [[ $output =~ $r ]]
    done

    # For each directory, we want a correct error if it’s not a directory.
    for d in $dirs tmp; do
        echo "not a directory: ${d}"
        rmdir "${img}/${d}"
        touch "${img}/${d}"
        run ch-run "$img" -- /bin/true
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
    run ch-run --private-tmp "$img" -- /bin/true
    mkdir "${img}/tmp"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/tmp: No such file or directory"
    echo "expected: ${r}"
    [[ $output =~ $r ]]

    # --home
    # FIXME: Not sure how to make the second mount(2) fail.
    rmdir "${img}/home"
    run ch-run --home "$img" -- /bin/true
    mkdir "${img}/home"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/home: No such file or directory"
    echo "expected: ${r}"
    [[ $output =~ $r ]]

    # default shouldn’t care if /home is missing
    rmdir "${img}/home"
    run ch-run "$img" -- /bin/true
    mkdir "${img}/home"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): /bin/true: No such file or directory"* ]]

    # Everything should be restored and back to the original error.
    run ch-run "$img" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): /bin/true: No such file or directory"* ]]

    # At this point, there should be exactly two each of passwd and group
    # temporary files. Remove them.
    [[ $(find -H "$tmpdir" -maxdepth 1 -name 'ch-run_passwd*' | wc -l) -eq 2 ]]
    [[ $(find -H "$tmpdir" -maxdepth 1 -name 'ch-run_group*'  | wc -l) -eq 2 ]]
    rm -v "$tmpdir"/ch-run_{passwd,group}*
    [[ $(find -H "$tmpdir" -maxdepth 1 -name 'ch-run_passwd*' | wc -l) -eq 0 ]]
    [[ $(find -H "$tmpdir" -maxdepth 1 -name 'ch-run_group*'  | wc -l) -eq 0 ]]
}


@test 'UID and/or GID invalid on host' {
    scope standard
    uid_bad=8675309
    gid_bad=8675310

    # UID
    run ch-run -v --uid="$uid_bad" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"UID ${uid_bad} not found; using dummy info"* ]]

    # GID
    run ch-run -v --gid="$gid_bad" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"GID ${gid_bad} not found; using dummy info"* ]]

    # both
    run ch-run -v --uid="$uid_bad" --gid="$gid_bad" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"UID ${uid_bad} not found; using dummy info"* ]]
    [[ $output = *"GID ${gid_bad} not found; using dummy info"* ]]
}

@test 'syslog' {
    # This test depends on a fairly specific syslog configuration, so just do
    # it on GitHub Actions.
    [[ -n $GITHUB_ACTIONS ]] || skip 'GitHub Actions only'
    [[ -n $CH_TEST_SUDO ]] || skip 'sudo required'
    expected="uid=$(id -u) args=6: ch-run ${ch_timg} -- echo foo \"b a}\\\$r\""
    echo "$expected"
    #shellcheck disable=SC2016
    ch-run "$ch_timg" -- echo foo  'b a}$r'
    text=$(sudo tail -n 10 /var/log/syslog)
    echo "$text"
    echo "$text" | grep -F "$expected"
}

@test 'reprint warnings' {
    run ch-run --warnings=0
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -Fc 'this is warning 1!') -eq 0 ]]
    [[ $(echo "$output" | grep -Fc 'this is warning 2!') -eq 0 ]]
    [[ "$output" != *'reprinting first'* ]]

    run ch-run --warnings=1
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output == *'ch-run['*']: warning: reprinting first 1 warning(s)'* ]]
    [[ $(echo "$output" | grep -Fc 'this is warning 1!') -eq 2 ]]
    [[ $(echo "$output" | grep -Fc 'this is warning 2!') -eq 0 ]]

    # Warnings list is a statically sized memory buffer. Ensure it works as
    # intended by printing more warnings than can be saved to this buffer.
    run ch-run --warnings=100
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output == *'ch-run['*']: warning: reprinting first 52 warning(s)'* ]]
    [[ $(echo "$output" | grep -Fc 'this is warning 52!') -eq 2 ]]
    [[ $(echo "$output" | grep -Fc 'this is warning 53!') -eq 1 ]]

}
