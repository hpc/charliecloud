true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope full
    prerequisites_ok obspy
}

@test "${ch_tag}/hello" {
    ch-run -b "$BATS_TMPDIR":/mnt "$ch_img" -- /hello.py

    # Validate the plot is large enough for non-trivial content. (When I wrote
    # this test, it was 74KiB.) Leave it for manual examination if desired.
    [[ $(stat -c '%s' "$BATS_TMPDIR"/obspy.pdf) -gt 65536 ]]
}
