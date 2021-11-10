true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok "rstudio"
}

# Test that we can login to rstudio
@test "${ch_tag}/test rstudio-server" {
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


# Test local Rstudio installation. Verifies programming environemnt works.  
@test "${ch_tag}/test R installation" {
    ch-run -b "$BATS_TMPDIR":/mnt/0 "$ch_img" -- bash -c "Rscript /rstudio/model.R"
    run ch-run -b "$BATS_TMPDIR":/mnt/0 "$ch_img" -b "$CHTEST_EXAMPLES_DIR"/rstudio:/mnt/1 -- bash -c "compare -metric AE /mnt/0/plot.png /mnt/1/plot.png null:"
    echo $output
    [[ $output = *'0'* ]]
}
