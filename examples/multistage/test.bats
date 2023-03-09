true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    prerequisites_ok multistage
}

@test "${ch_tag}/hello" {
    run ch-run "$ch_img" -- hello -g 'Hello, Charliecloud!'
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'Hello, Charliecloud!' ]]
}

@test "${ch_tag}/man hello" {
    ch-run "$ch_img" -- man hello > /dev/null
}

@test "${ch_tag}/files seem OK" {
    [[ $CH_TEST_PACK_FMT = squash-mount ]] && skip 'need directory image'
    # hello executable itself.
    test -x "${ch_img}/usr/local/bin/hello"
    # Present by default.
    test -d "${ch_img}/usr/local/share/applications"
    test -d "${ch_img}/usr/local/share/info"
    test -d "${ch_img}/usr/local/share/man"
    # Copied from first stage.
    test -d "${ch_img}/usr/local/share/locale"
    # Correct file count in directories.
    ls -lh "${ch_img}/usr/local/bin"
    [[ $(find "${ch_img}/usr/local/bin" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]]
    ls -lh "${ch_img}/usr/local/share"
    [[ $(find "${ch_img}/usr/local/share" -mindepth 1 -maxdepth 1 | wc -l) -eq 4 ]]
}

@test "${ch_tag}/no first-stage stuff present" {
    # Can’t run GCC.
    run ch-run "$ch_img" -- gcc --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'gcc: No such file or directory'* ]]

    # No GCC or Make.
    ls -lh "${ch_img}/usr/bin/gcc" || true
    ! test -f "${ch_img}/usr/bin/gcc"
    ls -lh "${ch_img}/usr/bin/make" || true
    ! test -f "${ch_img}/usr/bin/make"
}
