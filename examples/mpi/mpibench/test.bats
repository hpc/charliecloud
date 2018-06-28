load ../../../test/common
load ./test

# Note: This file is common for both mpihello flavors. Flavor-specific setup
# is in test.bash.

setup () {
    setup_specific
    scope full
    IMB_MPI1=/usr/local/src/mpi-benchmarks/src/IMB-MPI1

    # - One iteration because we just care about correctness, not performance.
    #   (If we let the benchmark choose, there is an overwhelming number of
    #   errors when MPI calls start failing, e.g. if CMA isn't working, and
    #   this makes the test take really long.)
    #
    # - Large -npmin because we only want to test all cores.
    #
    IMB_ARGS="-iter 1 -npmin 1000000000"
}

check_errors () {
    [[ ! $1 =~ 'errno =' ]]
}

check_finalized () {
    [[ $1 =~ 'All processes entering MPI_Finalize' ]]
}

check_process_ct () {
    ranks_expected=$1
    echo "ranks expected: $ranks_expected"
    ranks_found=$(  echo "$output" \
                  | fgrep '#processes =' \
                  | sed -r 's/^.+#processes = ([0-9]+)\s+$/\1/')
    echo "ranks found: $ranks_found"
    [[ $ranks_found -eq $ranks_expected ]]
}

# one from "Single Transfer Benchmarks"
@test "$EXAMPLE_TAG/pingpong (guest launch)" {
    run ch-run $IMG -- mpirun $CHTEST_MPIRUN_NP $IMB_MPI1 $IMB_ARGS PingPong
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct 2 "$output"
    check_finalized "$output"
}
@test "$EXAMPLE_TAG/pingpong (host launch)" {
    multiprocess_ok
    run $MPIRUN_CORE ch-run --join $IMG -- $IMB_MPI1 $IMB_ARGS PingPong
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct 2 "$output"
    check_finalized "$output"
}

# one from "Parallel Transfer Benchmarks"
@test "$EXAMPLE_TAG/sendrecv (guest launch)" {
    run ch-run $IMG -- mpirun $CHTEST_MPIRUN_NP $IMB_MPI1 $IMB_ARGS Sendrecv
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct $CHTEST_CORES_NODE "$output"
    check_finalized "$output"
}
@test "$EXAMPLE_TAG/sendrecv (host launch)" {
    multiprocess_ok
    run $MPIRUN_CORE ch-run --join $IMG -- $IMB_MPI1 $IMB_ARGS Sendrecv
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct $CHTEST_CORES_TOTAL "$output"
    check_finalized "$output"
}

# one from "Collective Benchmarks"
@test "$EXAMPLE_TAG/allreduce (guest launch)" {
    run ch-run $IMG -- mpirun $CHTEST_MPIRUN_NP $IMB_MPI1 $IMB_ARGS Allreduce
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct $CHTEST_CORES_NODE "$output"
    check_finalized "$output"
}
@test "$EXAMPLE_TAG/allreduce (host launch)" {
    multiprocess_ok
    run $MPIRUN_CORE ch-run --join $IMG -- $IMB_MPI1 $IMB_ARGS Allreduce
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct $CHTEST_CORES_TOTAL "$output"
    check_finalized "$output"
}
