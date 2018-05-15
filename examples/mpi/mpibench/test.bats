load ../../../test/common

setup () {
      scope full
      prerequisites_ok mpibench
      multiprocess_ok
      IMG=$IMGDIR/mpibench
      IMB_MPI1=/usr/local/src/mpi-benchmarks/src/IMB-MPI1

      # - One iteration because we just care about correctness, not
      #   performance. (If we let the benchmark choose, there is an
      #   overwhelming number of errors when MPI calls start failing, e.g. if
      #   CMA isn't working, and this makes the test take really long.)
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
@test "$EXAMPLE_TAG/pingpong" {
    run $MPIRUN_CORE ch-run $IMG -- $IMB_MPI1 $IMB_ARGS PingPong
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct 2 "$output"
    check_finalized "$output"
}

# one from "Parallel Transfer Benchmarks"
@test "$EXAMPLE_TAG/sendrecv" {
    run $MPIRUN_CORE ch-run $IMG -- $IMB_MPI1 $IMB_ARGS Sendrecv
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct $CHTEST_CORES_TOTAL "$output"
    check_finalized "$output"
}

# one from "Collective Benchmarks"
@test "$EXAMPLE_TAG/allreduce" {
    run $MPIRUN_CORE ch-run $IMG -- $IMB_MPI1 $IMB_ARGS Allreduce
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct $CHTEST_CORES_TOTAL "$output"
    check_finalized "$output"
}
