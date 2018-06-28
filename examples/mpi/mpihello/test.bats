load ../../../test/common
load ./test

# Note: This file is common for both mpihello flavors. Flavor-specific setup
# is in test.bash.

count_ranks () {
      echo "$1" \
    | egrep '^0: init ok' \
    | tail -1 \
    | sed -r 's/^.+ ([0-9]+) ranks.+$/\1/'
}

@test "$EXAMPLE_TAG/serial" {
    # This seems to start up the MPI infrastructure (daemons, etc.) within the
    # guest even though there's no mpirun.
    run ch-run $IMG -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output =~ ' 1 ranks' ]]
    [[ $output =~ '0: send/receive ok' ]]
    [[ $output =~ '0: finalize ok' ]]
}

@test "$EXAMPLE_TAG/guest starts ranks" {
    run ch-run $IMG -- mpirun $CHTEST_MPIRUN_NP /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(count_ranks "$output")
    echo "found $rank_ct ranks, expected $CHTEST_CORES_NODE"
    [[ $rank_ct -eq $CHTEST_CORES_NODE ]]
    [[ $output =~ '0: send/receive ok' ]]
    [[ $output =~ '0: finalize ok' ]]
}

@test "$EXAMPLE_TAG/host starts ranks" {
    multiprocess_ok
    echo $CHTEST_MPI
    echo "starting ranks with: $MPIRUN_CORE"

    GUEST_MPI=$(ch-run $IMG -- mpirun --version | head -1)
    echo "guest MPI: $GUEST_MPI"

    run $MPIRUN_CORE ch-run --join $IMG -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(count_ranks "$output")
    echo "found $rank_ct ranks, expected $CHTEST_CORES_TOTAL"
    [[ $rank_ct -eq $CHTEST_CORES_TOTAL ]]
    [[ $output =~ '0: send/receive ok' ]]
    [[ $output =~ '0: finalize ok' ]]
}
