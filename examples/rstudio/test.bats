true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope full
    prerequisites_ok "rstudio"
}

@test "${ch_tag}/test rstudio-server" {
    # Start up on port 8991
    run ch-run "$ch_img" -- start_rstudio 8991 &
    rstudio_server=$!
    run ch-run "$ch_img" -- python3 test_rstudio.py
    echo $output
    [[ $status -eq 0 ]]
    [[ $output = *'Good'* ]] 
    kill -9 $rstudio_server
}


# Test R installation 
@test "${ch_tag}/test R installation" {
    ch-run -b "$BATS_TMPDIR":/mnt "$ch_img" -- bash -c "Rscript model.R /mnt/plot.png"
    run ch-run -b "$BATS_TMPDIR":/mnt/0 -b "$CHTEST_EXAMPLES_DIR"/rstudio:/mnt/1 \
          "$ch_img" -- sh -c "./compare.sh /mnt/0/plot.png /mnt/1/plot.png"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'Images are equal'* ]]
}
