load ../../../test/common

setup () {
      IMG=$IMGDIR/mpihello
}

@test "$EXAMPLE_TAG/no mpirun" {
    # This seems to start up the MPI infrastructure (daemons, etc.) within the
    # guest even though there's no mpirun.
    run ch-run $IMG -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output =~ ' 1 ranks' ]]
    [[ $output =~ '0: send/receive ok' ]]
    [[ $output =~ '0: finalize ok' ]]
}

@test "$EXAMPLE_TAG/mpirun from guest" {
    run ch-run $IMG -- mpirun /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(echo "$output" | fgrep 'ranks' | wc -l)
    echo "found $rank_ct ranks"
    [[ $rank_ct -eq $CHTEST_CORES ]]
    [[ $output =~ '0: send/receive ok' ]]
    [[ $output =~ '0: finalize ok' ]]
}

@test "$EXAMPLE_TAG/mpirun from host" {
    # Lengthy check if we should actually try it.
    ( command -v mpirun 2>&1 > /dev/null ) || skip 'no mpirun in path'
    HOST_MPI=$(mpirun --version | head -1)
    echo "host MPI:  $HOST_MPI"
    GUEST_MPI=$(ch-run $IMG -- mpirun --version | head -1)
    echo "guest MPI: $GUEST_MPI"
    [[ $HOST_MPI =~ 'Open MPI' ]] || skip 'host mpirun is not OpenMPI'
    re='[0-9]+\.[0-9]+'  # check major and minor versions but not patch level
    [[ $HOST_MPI =~ $re ]]
    HV=$BASH_REMATCH
    echo "host version:  $HV"
    [[ $GUEST_MPI =~ $re ]]
    GV=$BASH_REMATCH
    echo "guest version: $GV"
    [[ $HV = $GV ]] || skip "MPI versions: host $HV, guest $GV"
    # Actual test.
    run mpirun ch-run $IMG -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(echo "$output" | fgrep 'ranks' | wc -l)
    echo "found $rank_ct ranks"
    [[ $rank_ct -eq $CHTEST_CORES ]]
    [[ $output =~ '0: send/receive ok' ]]
    [[ $output =~ '0: finalize ok' ]]
}
