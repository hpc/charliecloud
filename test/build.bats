load common

@test 'documentation seems sane' {
    scope standard
    command -v sphinx-build > /dev/null 2>&1 || skip 'Sphinx is not installed'
    if [[ ! -d ../doc ]]; then
        skip 'documentation source code absent'
    fi
    if [[ ! -f ../doc/html/index.html || ! -f ../doc/man/ch-run.1 ]]; then
        skip 'documentation not all built'
    fi
    (cd ../doc && make -j "$(getconf _NPROCESSORS_ONLN)")
    ./docs-sane
}

@test 'version number seems sane' {
    echo "version: ${ch_version}"
    [[ $(echo "$ch_version" | wc -l) -eq 1 ]]   # one line
    [[ $ch_version =~ ^0\.[0-9]+(\.[0-9]+)? ]]  # starts with right numbers
    diff -u <(echo "$ch_version") "${ch_base}/libexec/charliecloud/version.txt"
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
        diff -u <(echo "${output}") <(echo "$ch_version")
        # --help: returns 0, says "Usage:" somewhere.
        run "$path" --help
        echo "$output"
        [[ $status -eq 0 ]]
        [[ $output = *'sage:'* ]]
        # Most, but not all, executables should print usage and exit
        # unsuccessfully when run without arguments.
        case $filename in
            ch-checkns|ch-test)
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

@test 'ch-build --builder-info' {
    scope standard
    ch-build --builder-info
}

@test 'lint shell scripts' {
    scope standard
    ( command -v shellcheck >/dev/null 2>&1 ) || skip "no shellcheck found"
    # skip if minimum shellcheck not met unless Travis or LANL
    version=$(shellcheck --version | grep -E '^version:' | cut -d' ' -f2)
    major=${version%%.*}
    rest=${version#*.}
    minor=${rest%%.*}
    echo "shellcheck: version '$version', major '$major', minor '$minor'"
    if [[ $minor -lt 6 ]]; then
        # no need to check major because minimum is 0
        error="shellcheck $version older than 0.6.0"
        if [[ $TRAVIS ]] || [[ $(hostname --fqdn) = *'.lanl.gov' ]]; then
            echo "$error"
            false
        else
            skip "$error"
        fi
    fi
    # user executables
    for i in "$ch_bin"/ch-*; do
        echo "shellcheck: ${i}"
        [[ ! $(file "$i") = *'shell script'* ]] && continue
        shellcheck -e SC1090,SC2002,SC2154 "$i"
    done
    # libraries for user executables
    for i in "$ch_libexec"/*.sh; do
        echo "shellcheck: ${i}"
        shellcheck -s sh -e SC1090,SC2002 "$i"
    done
    # BATS scripts
    #
    # The sed horror encapsulated here is because BATS requires that the curly
    # open brace after @test be on the same line, while ShellCheck requires
    # that it not be (otherwise parse error). Thus, line numbers are wrong.
    while IFS= read -r -d '' i; do
        echo "shellcheck: ${i}"
          sed -r $'s/(@test .+) \{/\\1\\\n{/g' "$i" \
        | shellcheck -s bash -e SC1090,SC2002,SC2154,SC2164 -
    done < <( find . "$CHTEST_EXAMPLES_DIR" -name '*.bats' -print0 )
    # libraries for BATS scripts
    shellcheck -s bash -e SC2002,SC2034 ./common.bash
    # misc shell scripts
    if [[ -e ../packaging ]]; then
        misc=". ../examples ../packaging"
    else
        misc=". ../examples"
    fi
    shellcheck -e SC2002,SC2034 "${CHTEST_EXAMPLES_DIR}/chtest/Build"
    # shellcheck disable=SC2086
    while IFS= read -r -d '' i; do
        echo "shellcheck: ${i}"
        shellcheck -e SC2002 "$i"
    done < <( find $misc -name bats -prune \
                         -o \( -name '*.sh' -o -name '*.bash' \) -print0 )
}

@test 'proxy variables' {
    scope quick
    # Proxy variables are a mess on UNIX. There are a lot them, and different
    # programs use them inconsistently. This test is based on the assumption
    # that if one of the proxy variables are set, then they all should be, in
    # order to prepare for diverse internet access at build time.
    #
    # Coordinate this test with bin/ch-build.
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

@test 'sotest executable works' {
    scope quick
    export LD_LIBRARY_PATH=./sotest
    ldd sotest/sotest
    sotest/sotest
}
