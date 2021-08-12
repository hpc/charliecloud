true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok obspy
}

@test "${ch_tag}/hello" {
    ch-run -b "$BATS_TMPDIR":/mnt "$ch_img" -- /hello.py /mnt/obspy.png

    # Compare reference image to generated image.
    cmp "$CHTEST_EXAMPLES_DIR"/obspy/obspy.png "$BATS_TMPDIR"/obspy.png
}
