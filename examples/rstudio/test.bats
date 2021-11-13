true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok "rstudio"
}


@test "${ch_tag}/R itself" {
    # Compute regression and check results.
    run ch-run -b "$BATS_TMPDIR":/mnt/0 "$ch_img" -- Rscript /rstudio/model.R
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'(Intercept) -17.5791'* ]]
    [[ $output = *'speed         3.9324'* ]]

    # Check pixels (not metadata) against the reference plot. This uses
    # ImageMagick's similarity metric “AE”, which is simply a count of pixels
    # that are different [1]. If this is non-zero, you can look at
    # $BATS_TMPDIR/diff.png, which highlights the differing pixels in red.
    #
    # [1]: https://imagemagick.org/script/command-line-options.php#metric
    run ch-run -b "$BATS_TMPDIR":/mnt/0 "$ch_img" -- \
        compare -metric AE /rstudio/plot.png /mnt/0/plot.png /mnt/0/diff.png
    echo
    echo "$output"
    [[ $status -eq 0 ]]  # should be zero if images equal
    [[ $output = '0' ]]  # entire output is number of differing pixels
}


# Test that we can login to rstudio
@test "${ch_tag}/test rstudio-server" {
    skip
    # Start up on port 8991
    # If a previous test failed kill rserver before we begin
    rstudio_server=$(pgrep -f "rserver --www-port=8991" || exit 0)
    [[ ! -z "$rstudio_server" ]] && kill $rstudio_server
    ch-run "$ch_img" -- python3 /rstudio/run.py
    sleep 5
    rstudio_server=$(pgrep -f "rserver --www-port=8991")
    run ch-run "$ch_img" -- python3 /rstudio/test_rstudio.py
    echo $output
    [[ $status -eq 0 ]]
    [[ $output = *'Rstudio login successful!'* ]] 
    kill $rstudio_server
}


