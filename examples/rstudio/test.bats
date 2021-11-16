true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok "rstudio"
    [[ $CH_TEST_PACK_FMT = *-unpack ]] || skip 'issue #1161'
    pid_file=${BATS_TMPDIR}/rserver.pid
    pw_file=${BATS_TMPDIR}/rserver-password.txt
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


# I was not able to find any docs for rserver command line arguments online.
# However you can see them with:
#
#   $ ch-run $CH_TEST_IMGDIR/rstudio -- \
#            /usr/lib/rstudio-server/bin/rserver --help
@test "${ch_tag}/start rstudio-server" {
    # Generate a random password for logging into RStudio; read by
    # rserver-auth.sh. This basic measure prevents other users on the system
    # from connecting. We use a file rather than an environment variable so
    # later tests can use it.
    openssl rand -base64 18 > "$pw_file"
    # Cleanup possibly left-over files from previous run.
    rm -Rf --one-file-system "$pid_file" \
                             "$BATS_TMPDIR"/rstudio-os.sqlite \
                             "$BATS_TMPDIR"/rstudio-session \
                             "$BATS_TMPDIR"/rstudio-server
    # Start RStudio Server. Port is arbitrary.
    ch-run "$ch_img" -- /usr/lib/rstudio-server/bin/rserver \
                        --www-port=8991 \
                        --www-address=127.0.0.1 \
                        --server-daemonize=1 \
                        --server-pid-file="$pid_file" \
                        --server-user="$USER" \
                        --server-data-dir="$BATS_TMPDIR" \
                        --auth-none=0 \
                        --auth-encrypt-password=0 \
                        --auth-pam-helper-path=/rstudio/rserver-auth.sh \
                        --verify-installation=1
    # Wait for startup to complete (PID file appears).
    for i in {1..10}; do
        if [[ -f $pid_file ]]; then
            break
        fi
        sleep 1
    done
    [[ $i -lt 10 ]]
}


@test "${ch_tag}/stop rstudio-server" {
    [[ -f $pid_file ]]
    pid=$(cat $pid_file)
    kill "$pid"
    # Wait for RStudio Server to exit.
    for i in {1..10}; do
        if [[ ! -d /proc/$i ]]; then
            break
        fi
    done
    [[ $i -lt 10 ]]
    # Make sure no process named like our rserver(1) exists.
    ! pgrep -f 'rserver --www-port=8991'
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


