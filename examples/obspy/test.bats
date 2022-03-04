true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok obspy
}

@test "${ch_tag}/hello" {
    # Remove prior test's plot to avoid using it if something else breaks.
    rm -f "$BATS_TMPDIR"/obspy.png

    ch-run -b "$BATS_TMPDIR":/mnt "$ch_img" -- /hello.py /mnt/obspy.png
}

@test "${ch_tag}/hello PNG" {
    pict_ok
    pict_assert_equal "$CHTEST_EXAMPLES_DIR"/obspy/obspy.png \
                      "$BATS_TMPDIR"/obspy.png
}
