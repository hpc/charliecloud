true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok obspy
    indir=$CHTEST_EXAMPLES_DIR/obspy
    outdir=$BATS_TMPDIR/obspy
}

@test "${ch_tag}/hello" {
    # Remove prior test's plot to avoid using it if something else breaks.
    mkdir -p "$outdir"
    rm -f "$outdir"/obspy.png
    ch-run -b "${outdir}:/mnt" "$ch_img" -- /hello.py /mnt/obspy.png
}

@test "${ch_tag}/hello PNG" {
    pict_ok
    pict_assert_equal "${indir}/obspy.png" \
                      "${outdir}/obspy.png" 1
}
