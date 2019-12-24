load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok hello
}

@test "${ch_tag}/hello" {
    run ch-run "$ch_img" -- /hello/hello.sh
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'hello world' ]]
}

@test "${ch_tag}/distribution sanity" {
    # Try various simple things that should work in a basic Debian
    # distribution. (This does not test anything Charliecloud manipulates.)
    ch-run "$ch_img" -- /bin/bash -c true
    ch-run "$ch_img" -- /bin/true
    ch-run "$ch_img" -- find /etc -name 'a*'
    ch-run "$ch_img" -- sh -c 'echo foo | /bin/grep -E foo'
    ch-run "$ch_img" -- nice true
}
