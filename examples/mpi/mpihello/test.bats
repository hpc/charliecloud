load ../../../test/common

setup () {
      scope full
      IMG=$IMGDIR/mpihello
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
    run ch-run $IMG -- mpirun /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(echo "$output" | fgrep 'ranks' | wc -l)
    echo "found $rank_ct ranks, expected $CHTEST_CORES_NODE"
    [[ $rank_ct -eq $CHTEST_CORES_NODE ]]
    [[ $output =~ '0: send/receive ok' ]]
    [[ $output =~ '0: finalize ok' ]]
}

@test "$EXAMPLE_TAG/host starts ranks" {

    multiprocess_ok
    echo "starting ranks with: $MPIRUN_CORE"

    HOST_MPI=$(mpirun --version | head -1)
    echo "host MPI:  $HOST_MPI"
    GUEST_MPI=$(ch-run $IMG -- mpirun --version | head -1)
    echo "guest MPI: $GUEST_MPI"
    [[ $HOST_MPI =~ 'Open MPI' ]] || skip 'host mpirun is not OpenMPI'
    re='[0-9]+\.[0-9]+\.[0-9]+'
    [[ $HOST_MPI =~ $re ]]
    HV=$BASH_REMATCH
    echo "host version:  $HV"
    [[ $GUEST_MPI =~ $re ]]
    GV=$BASH_REMATCH
    echo "guest version: $GV"
    [[ $HV = $GV ]] || skip "MPI versions: host $HV, guest $GV"
    # Actual test.
    run $MPIRUN_CORE ch-run --join $IMG -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(echo "$output" | fgrep 'ranks' | wc -l)
    echo "found $rank_ct ranks, expected $CHTEST_CORES_TOTAL"
    [[ $rank_ct -eq $CHTEST_CORES_TOTAL ]]
    [[ $output =~ '0: send/receive ok' ]]
    [[ $output =~ '0: finalize ok' ]]
}
