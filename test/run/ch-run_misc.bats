load ../common


@test 'relative path to image' {  # issue #6
    scope quick
    cd "$(dirname "$ch_timg")" && ch-run "$(basename "$ch_timg")" -- /bin/true
}


@test 'symlink to image' {  # issue #50
    scope quick
    ln -sf "$ch_timg" "${BATS_TMPDIR}/symlink-test"
    ch-run "${BATS_TMPDIR}/symlink-test" -- /bin/true
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
    # Note: --ch-ssh without /usr/bin/ch-ssh is in test "broken image errors".
    scope quick
    ls -l "$ch_bin/ch-ssh"
    ch-run --ch-ssh "$ch_timg" -- ls -l /usr/bin/ch-ssh
    ch-run --ch-ssh "$ch_timg" -- test -x /usr/bin/ch-ssh
    # Test bind-mount by comparing size rather than e.g. "ch-ssh --version"
    # because ch-ssh won't run on Alpine (issue #4).
    host_size=$(stat -c %s "${ch_bin}/ch-ssh")
    guest_size=$(ch-run --ch-ssh "$ch_timg" -- stat -c %s /usr/bin/ch-ssh)
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
@test '$CH_RUNNING' {
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
    [[ $output = *'cannot find home directory: is $HOME set?'* ]]

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
    run ch-run --cd /goops "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ "can't cd to /goops: No such file or directory" ]]
}


@test 'ch-run --bind' {
    scope quick

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

    # omit tmpfs at /home, which shouldn't be empty
    ch-run --no-home "$ch_timg" -- cat /home/overmount-me
    # overmount tmpfs at /home
    ch-run -b "${ch_imgdir}/bind1:/home" "$ch_timg" -- cat /home/file1
    # bind to /home without overmount
    ch-run --no-home -b "${ch_imgdir}/bind1:/home" "$ch_timg" \
           -- cat /home/file1
    # omit default /home, with unrelated --bind
    ch-run --no-home -b "${ch_imgdir}/bind1" "$ch_timg" \
           -- cat "${ch_imgdir}/bind1/file1"
}


@test 'ch-run --bind errors' {
    scope quick

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
    [[ $output = *"can't bind: /tmp not subdirectory of ${ch_timg}"* ]]

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
    # "printenv" or "env", though it does round-trip through Bash "set":
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

@test 'ch-run --set-env from Dockerfile' {
    scope standard
    prerequisites_ok argenv
    img=${ch_imgdir}/argenv

    output_expected=$(cat <<'EOF'
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)

    run ch-run --set-env="${img}/ch/environment" "$img" -- \
               sh -c 'env | grep -E "^chse_"'
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
    [[ $output = *"--set-env: can't open:"* ]]

    # Note: I'm not sure how to test an error during reading, i.e., getline(3)
    # rather than fopen(3). Hence no test for "error reading".

    # invalid line: missing '='
    echo 'FOO bar' > "$f_in"
    run ch-run --set-env="$f_in" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"--set-env: no delimiter: ${f_in}:1"* ]]

    # invalid line: no name
    echo '=bar' > "$f_in"
    run ch-run --set-env="$f_in" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"--set-env: empty name: ${f_in}:1"* ]]
}

# shellcheck disable=SC2016
@test 'ch-run --set-env command line' {
    scope standard

    # missing '''
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
    echo "$output"
    [[ $status -eq 0 ]]
    ex='^(_|CH_RUNNING|HOME|PATH|SHLVL)='  # variables expected to change
    diff -u <(env | grep -Ev "$ex") <(echo "$output" | grep -Ev "$ex")

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

@test 'ch-run: squashfs' {
scope standard
    [[ $TEST_SQ == 'yes' ]] || skip 'no squashfuse'

    ch_sqfs="${CH_TEST_TARDIR}/00_tiny.sqfs"
    ch_mnt="/var/tmp/${USER}.ch/mnt"

    # default mount point
    run ch-run -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"using default mount point: ${ch_mnt}"* ]]

    [[ -d ${ch_mnt} ]]
    rmdir "${ch_mnt}"

    # -m option
    mountpt="${BATS_TMPDIR}/sqfs_tmpdir" #fix later
    mkdir "$mountpt"
    run ch-run -m "$mountpt" -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: ${mountpt}"* ]]

    # -m with non-sqfs img
    run ch-run -m "$mountpt" -v "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"warning: --mount invalid with directory image, ignoring"* ]]
    [[ $output = *"newroot: ${ch_timg}"* ]]

    # only create 1 directory
    run ch-run -m "$mountpt" -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: ${mountpt}"* ]]
    [[ -d "$mountpt" ]]
    rmdir "$mountpt"
}

@test 'ch-run: squashfs errors' {
    scope standard
    [[ $TEST_SQ == yes ]] || skip 'no squashfuse'

    ch_sqfs="${CH_TEST_TARDIR}"/00_tiny.sqfs

    # empty mount point
    run ch-run --mount= "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]] # exits with status of 139
    [[ $output = *"mount point can't be empty"* ]]

    # parent dir doesn't exist
    mountpt="${BATS_TMPDIR}/sq/mnt"
    run ch-run -m "$mountpt" "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]] # exits with status of 139
    [[ $output = *"can't stat mount point: ${mountpt}"* ]]

    # mount point contains a file, can't opendir but shouldn't make it
    run ch-run -m /var/tmp/file "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *"can't stat mount point: /var/tmp/file"* ]]

    # input is file but not sqfs
    run ch-run Build.missing -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"unknown image type: Build.missing"* ]]

    # input has same magic number but is broken
    sq_tmp="${CH_TEST_TARDIR}"/tmp.sqfs
    # copy over magic number from sqfs to broken sqfs
    dd if="$ch_sqfs" of="$sq_tmp" conv=notrunc bs=1 count=4
    run ch-run -vvv "$sq_tmp" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *"actual: 6873 7173"* ]]
    [[ $output = *"can't open SquashFS: ${sq_tmp}"* ]]
    rm "${sq_tmp}"
}
@test 'broken image errors' {
    scope standard
    img="${BATS_TMPDIR}/broken-image"

    # Create an image skeleton.
    dirs=$(echo {dev,proc,sys})
    files=$(echo etc/{group,passwd})
    # shellcheck disable=SC2116
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

    # For each required file, we want a correct error if it's missing.
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

    # For each optional file, we want no error if it's missing.
    for f in $files_optional; do
        echo "optional: ${f}"
        rm "${img}/${f}"
        run ch-run "$img" -- /bin/true
        touch "${img}/${f}"  # restore before test fails for idempotency
        echo "$output"
        [[ $status -eq 1 ]]
        [[ $output = *"can't execve(2): /bin/true: No such file or directory"* ]]
    done

    # For all files, we want a correct error if it's not a regular file.
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

    # For each directory, we want a correct error if it's missing.
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

    # For each directory, we want a correct error if it's not a directory.
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

    # /home without --private-home
    # FIXME: Not sure how to make the second mount(2) fail.
    rmdir "${img}/home"
    run ch-run "$img" -- /bin/true
    mkdir "${img}/home"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    r="can't mount tmpfs at /.+/home: No such file or directory"
    echo "expected: ${r}"
    [[ $output =~ $r ]]

    # --no-home shouldn't care if /home is missing
    rmdir "${img}/home"
    run ch-run --no-home "$img" -- /bin/true
    mkdir "${img}/home"  # restore before test fails for idempotency
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): /bin/true: No such file or directory"* ]]

    # --ch-ssh but no /usr/bin/ch-ssh
    run ch-run --ch-ssh "$img" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"--ch-ssh: /usr/bin/ch-ssh not in image"* ]]

    # Everything should be restored and back to the original error.
    run ch-run "$img" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't execve(2): /bin/true: No such file or directory"* ]]

    # At this point, there should be exactly two each of passwd and group
    # temporary files. Remove them.
    [[ $(find /tmp -maxdepth 1 -name 'ch-run_passwd*' | wc -l) -eq 2 ]]
    [[ $(find /tmp -maxdepth 1 -name 'ch-run_group*' | wc -l) -eq 2 ]]
    rm -v /tmp/ch-run_{passwd,group}*
    [[ $(find /tmp -maxdepth 1 -name 'ch-run_passwd*' | wc -l) -eq 0 ]]
    [[ $(find /tmp -maxdepth 1 -name 'ch-run_group*' | wc -l) -eq 0 ]]
}


@test 'UID and/or GID invalid on host' {
    scope standard
    uid_bad=8675309
    gid_bad=8675310

    # UID
    run ch-run -v --uid=$uid_bad "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"UID ${uid_bad} not found; using dummy info"* ]]

    # GID
    run ch-run -v --gid=$gid_bad "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"GID ${gid_bad} not found; using dummy info"* ]]

    # both
    run ch-run -v --uid=$uid_bad --gid=$gid_bad "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"UID ${uid_bad} not found; using dummy info"* ]]
    [[ $output = *"GID ${gid_bad} not found; using dummy info"* ]]
}
