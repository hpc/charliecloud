load ../common


@test 'documentation seems sane' {
    scope standard
    if ( ! command -v sphinx-build > /dev/null 2>&1 ); then
        skip 'Sphinx is not installed'
    fi
    if [[ ! -d ../doc ]]; then
        skip 'documentation source code absent'
    fi
    if [[ ! -f ../doc/html/index.html || ! -f ../doc/man/ch-run.1 ]]; then
        skip 'documentation not built'
    fi
    (cd ../doc && make -j "$(getconf _NPROCESSORS_ONLN)")
    ./docs-sane
}

@test 'version number seems sane' {
    # This checks the form of the version number but not whether it's
    # consistent with anything, because so far that level of strictness has
    # yielded hundreds of false positives but zero actual bugs.
    scope quick
    echo "version: ${ch_version}"
    re='^0\.[0-9]+(\.[0-9]+)?(~pre\+([A-Za-z0-9]+\.)?([0-9a-f]+(\.dirty)?)?)?$'
    [[ $ch_version =~ $re ]]
}

@test 'executables seem sane' {
    scope quick
    # Assume that everything in $ch_bin is ours if it starts with "ch-" and
    # either (1) is executable or (2) ends in ".c". Demand satisfaction from
    # each. The latter is to catch cases when we haven't compiled everything;
    # if we have, the test makes duplicate demands, but that's low cost.
    while IFS= read -r -d '' path; do
        path=${path%.c}
        filename=$(basename "$path")
        echo
        echo "$path"
        # --version
        run "$path" --version
        echo "$output"
        [[ $status -eq 0 ]]
        # --help: returns 0, says "Usage:" somewhere.
        run "$path" --help
        echo "$output"
        [[ $status -eq 0 ]]
        [[ $output = *'sage:'* ]]
        # Most, but not all, executables should print usage and exit
        # unsuccessfully when run without arguments.
        case $filename in
            ch-checkns)
                ;;
            *)
                run "$path"
                echo "$output"
                [[ $status -eq 1 ]]
                [[ $output = *'sage:'* ]]
                ;;
        esac
        # not setuid or setgid
        ls -l "$path"
        [[ ! -u $path ]]
        [[ ! -g $path ]]
    done < <( find "$ch_bin" -name 'ch-*' -a \( -executable -o -name '*.c' \) \
                   -print0 )
}

@test 'lint shell scripts' {
    # ShellCheck excludes used below:
    #
    #  SC2002  useless use of cat
    #  SC2164  cd exit code unchecked (Bats checks for failure)
    #
    # Additional excludes work around issue #210, and I think are required for
    # the Bats tests forever:
    #
    #  SC1090  can't find sourced file
    #  SC2154  variable referenced but not assigned
    #
    scope standard
    arch_exclude ppc64le  # no ShellCheck pre-built
    # Only do this test in build directory; the reasoning is that we don't
    # alter the shell scripts during install enough to re-test, and it means
    # we only have to find everything in one path.
    if [[ $CHTEST_INSTALLED ]]; then
        skip 'only in build directory'
    fi
    # ShellCheck present?
    if ( ! command -v shellcheck >/dev/null 2>&1 ); then
        pedantic_fail 'no ShellCheck found'
    fi
    # ShellCheck minimum version?
    version=$(shellcheck --version | grep -E '^version:' | cut -d' ' -f2)
    needed=0.7.2
    lesser=$(printf "%s\n%s\n" "$version" "$needed" | sort -V | head -1)
    echo "shellcheck: have ${version}, need ${needed}, lesser ${lesser}"
    if  [[ $lesser != "$needed" ]]; then
        pedantic_fail 'shellcheck too old'
    fi
    # Shell scripts and libraries: appropriate extension or shebang.
    # For awk program, see: https://unix.stackexchange.com/a/66099
    while IFS= read -r i; do
        echo "shellcheck: ${i}"
        shellcheck -x -P "$ch_lib" -e SC1090,SC2002,SC2154 "$i"
    done < <( find "$ch_base" \
                   \(    -name .git \
                      -o -name build-aux \) -prune \
                -o \( -name '*.sh' -print \) \
                -o \( -name '*.bash' -print \) \
                -o \( -type f -exec awk '/^#!\/bin\/(ba)?sh/ {print FILENAME}
                                         {nextfile}' {} + \) )
    # Bats scripts. Use sed to do two things:
    #
    # 1. Make parseable by ShellCheck by removing "@test '...'". This does
    #    remove the test names, but line numbers are still valid.
    #
    # 2. Remove preprocessor substitutions "%(foo)", which also confuse Bats.
    #
    while IFS= read -r i; do
        echo "shellcheck: ${i}"
          sed -r -e 's/@test (.+) \{/test_ () {/g' "$i" \
                 -e 's/%\(([a-zA-Z0-9_]+)\)/SUBST_\1/g' \
        | shellcheck -s bash -e SC1090,SC2002,SC2154,SC2164 -
    done < <( find "$ch_base" -name '*.bats' -o -name '*.bats.in' )
}

@test 'proxy variables' {
    scope quick
    # Proxy variables are a mess on UNIX. There are a lot them, and different
    # programs use them inconsistently. This test is based on the assumption
    # that if one of the proxy variables are set, then they all should be, in
    # order to prepare for diverse internet access at build time.
    #
    # Coordinate this test with common.bash:build_().
    #
    # Note: ALL_PROXY and all_proxy aren't currently included, because they
    # cause image builds to fail until Docker 1.13
    # (https://github.com/docker/docker/pull/27412).
    v=' no_proxy http_proxy https_proxy'
    v+=$(echo "$v" | tr '[:lower:]' '[:upper:]')
    empty_ct=0
    for i in $v; do
        if [[ -n ${!i} ]]; then
            echo "${i} is non-empty"
            for j in $v; do
                echo "  $j=${!j}"
                if [[ -z ${!j} ]]; then
                    (( ++empty_ct ))
                fi
            done
            break
        fi
    done
    [[ $empty_ct -eq 0 ]]
}
