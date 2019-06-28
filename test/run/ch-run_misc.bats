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
               "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_timg}/mnt/10"* ]]

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

    # source does not exist
    run ch-run -b "${ch_imgdir}/hoops" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_imgdir}/hoops"* ]]

    # destination does not exist
    run ch-run -b "${ch_imgdir}/bind1:/goops" "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_timg}/goops"* ]]

    # neither source nor destination exist
    run ch-run -b "${ch_imgdir}/hoops:/goops" "$ch_timg" -- /bin/true
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
               "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't bind: not found: ${ch_timg}/goops"* ]]
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
chse_b3=$PATH
 chse_b4=bar
chse_b5= bar

chse_c1=foo
chse_c1=bar
EOF
    cat "$f_in"
    output_expected=$(cat <<'EOF'
(' chse_b4', 'bar')
('chse_a1', 'bar')
('chse_a2', 'bar=baz')
('chse_a3', 'bar baz')
('chse_a4', 'bar')
('chse_a5', '')
('chse_a6', '')
('chse_a7', "''")
('chse_b1', '"bar"')
('chse_b2', 'bar # baz')
('chse_b3', '$PATH')
('chse_b5', ' bar')
('chse_c1', 'bar')
EOF
)
    run ch-run --set-env="$f_in" "$ch_timg" -- python3 -c 'import os; [print((k,v)) for (k,v) in sorted(os.environ.items()) if "chse_" in k]'
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")
}

@test 'ch-run --set-env from Dockerfile' {
    scope standard
    prerequisites_ok debian9
    img=${ch_imgdir}/debian9

    output_expected=$(cat <<'EOF'
chse_dockerfile=foo
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
    [[ $output = *"No such file or directory"* ]]

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

@test 'ch-run --unset-env' {
    scope standard

    export chue_1=foo
    export chue_2=bar

    printf '\n# Nothing\n\n'
    run ch-run --unset-env=doesnotmatch "$ch_timg" -- env
    echo "$output"
    [[ $status -eq 0 ]]
    ex='^(_|HOME|PATH)='  # variables expected to change
    diff -u <(env | grep -Ev "$ex") <(echo "$output" | grep -Ev "$ex")

    printf '\n# Everything\n\n'
    run ch-run --unset-env='*' "$ch_timg" -- env
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '' ]]

    printf '\n# Everything, plus shell re-adds\n\n'
    run ch-run --unset-env='*' "$ch_timg" -- /bin/sh -c env
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(printf 'SHLVL=1\nPWD=/\n') <(echo "$output")

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

@test 'broken image errors' {
    scope standard
    img="${BATS_TMPDIR}/broken-image"

    # Create an image skeleton.
    dirs=$(echo {dev,proc,sys})
    files=$(echo etc/{group,hosts,passwd,resolv.conf})
    # shellcheck disable=SC2116
    files_optional=  # formerly for ch-ssh (#378), but leave infrastructure
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
        r="can't bind: not found: .+/${f}"
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
        r="can't bind: not found: .+/${d}"
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
