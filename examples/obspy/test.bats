true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope full
    indir=${CHTEST_EXAMPLES_DIR}/obspy
    inbind=${indir}:/mnt/0
    outdir=$BATS_TMPDIR
    outbind=${outdir}:/mnt/1
    prerequisites_ok obspy
}

@test "${ch_tag}/hello" {
    ch-run -b "$inbind" -b "$outbind" "$ch_img" -- sh -c "/hello.py \
                                                   /mnt/1/obspy.png"

    # Validate the plot is large enough for non-trivial content. (When I wrote
    # this test, it was 74KiB.) Leave it for manual examination if desired.
    [[ $(stat -c '%s' "$BATS_TMPDIR"/obspy.pdf) -gt 65536 ]]

    # Compare the image to a previous run
    cmp "${indir}/obspy.png" "${outdir}/obspy.png"
}
