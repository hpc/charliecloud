true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok distroless
}

@test "${ch_tag}/hello" {
    run ch-run "$ch_img" -- /distroless/hello.py
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'Hello, World!' ]]
}
