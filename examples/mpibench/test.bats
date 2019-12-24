load "${CHTEST_DIR}/common.bash"

setup () {
    scope full
    prerequisites_ok "$ch_tag"

    # One iteration on most of these tests because we just care about
    # correctness, not performance. (If we let the benchmark choose, there is
    # an overwhelming number of errors when MPI calls start failing, e.g. if
    # CMA isn't working, and this makes the test take really long.)
    #
    # Large -npmin because we only want to test all cores.
    imb_mpi1=/usr/local/src/mpi-benchmarks/src/IMB-MPI1
    imb_args="-iter 1 -npmin 1000000000"

    # On the HSN performance test, we do want to run multiple iterations to
    # reduce variability. The benchmark will automatically scale down the
    # number of iterations based on the expected run time, disabling that so
    # we get more consistent results. Npmin is ommitted as we are only running
    # with two processes, one per node.
    imb_perf_args="-iter 100 -iter_policy off"
}

check_errors () {
    [[ ! "$1" =~ 'errno =' ]]
}

check_finalized () {
    [[ "$1" =~ 'All processes entering MPI_Finalize' ]]
}

check_process_ct () {
    ranks_expected="$1"
    echo "ranks expected: ${ranks_expected}"
    ranks_found=$(  echo "$output" \
                  | grep -F '#processes =' \
                  | sed -r 's/^.+#processes = ([0-9]+)\s+$/\1/')
    echo "ranks found: ${ranks_found}"
    [[ $ranks_found -eq "$ranks_expected" ]]
}

# one from "Single Transfer Benchmarks"
@test "${ch_tag}/pingpong (guest launch)" {
    # shellcheck disable=SC2086
    run ch-run $ch_unslurm "$ch_img" -- \
               mpirun $ch_mpirun_np "$imb_mpi1" $imb_args PingPong
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct 2 "$output"
    check_finalized "$output"
}

# one from "Parallel Transfer Benchmarks"
@test "${ch_tag}/sendrecv (guest launch)" {
    # shellcheck disable=SC2086
    run ch-run $ch_unslurm "$ch_img" -- \
               mpirun $ch_mpirun_np "$imb_mpi1" $imb_args Sendrecv
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct "$ch_cores_node" "$output"
    check_finalized "$output"
}

# one from "Collective Benchmarks"
@test "${ch_tag}/allreduce (guest launch)" {
    # shellcheck disable=SC2086
    run ch-run $ch_unslurm "$ch_img" -- \
               mpirun $ch_mpirun_np "$imb_mpi1" $imb_args Allreduce
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct "$ch_cores_node" "$output"
    check_finalized "$output"
}

@test "${ch_tag}/crayify image" {
    crayify_mpi_or_skip "$ch_img"
}

# This test compares OpenMPI's point to point bandwidth with all high speed
# plugins enabled against the performance just using TCP. Pass if HSN
# performance is at least double TCP.
@test "${ch_tag}/using the high-speed network (host launch)" {
    multiprocess_ok
    [[ $ch_multinode ]] || skip "multinode only"
    [[ $ch_cray ]] && skip "Cray doesn't support running on tcp"
    # Verify we have known HSN devices present. (Note that -d tests for
    # directory, not device.)
    [[ ! -d /dev/infiniband ]] && skip "No high speed network detected"
    # shellcheck disable=SC2086
    hsn_enabled_bw=$($ch_mpirun_2_2node ch-run "$ch_img" -- \
                     "$imb_mpi1" $imb_perf_args Sendrecv | tail -n +35 \
                     | sort -nrk6 | head -1 | awk '{print $6}')
    # Configure network transport plugins to TCP only.
    export OMPI_MCA_pml=ob1
    export OMPI_MCA_btl=tcp,self
    # shellcheck disable=SC2086
    hsn_disabled_bw=$($ch_mpirun_2_2node ch-run "$ch_img" -- \
                      "$imb_mpi1" $imb_perf_args Sendrecv | tail -n +35 \
                      | sort -nrk6 | head -1 | awk '{print $6}')
    echo "Max bandwidth with high speed network: $hsn_enabled_bw MB/s"
    echo "Max bandwidth without high speed network: $hsn_disabled_bw MB/s"
    [[ ${hsn_disabled_bw%\.*} -lt $((${hsn_enabled_bw%\.*} / 2)) ]]
}

@test "${ch_tag}/pingpong (host launch)" {
    multiprocess_ok
    # shellcheck disable=SC2086
    run $ch_mpirun_core ch-run --join "$ch_img" -- \
                               "$imb_mpi1" $imb_args PingPong
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct 2 "$output"
    check_finalized "$output"
}

@test "${ch_tag}/sendrecv (host launch)" {
    multiprocess_ok
    # shellcheck disable=SC2086
    run $ch_mpirun_core ch-run --join "$ch_img" -- \
                               "$imb_mpi1" $imb_args Sendrecv
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct "$ch_cores_total" "$output"
    check_finalized "$output"
}

@test "${ch_tag}/allreduce (host launch)" {
    multiprocess_ok
    # shellcheck disable=SC2086
    run $ch_mpirun_core ch-run --join "$ch_img" -- \
                               "$imb_mpi1" $imb_args Allreduce
    echo "$output"
    [[ $status -eq 0 ]]
    check_errors "$output"
    check_process_ct "$ch_cores_total" "$output"
    check_finalized "$output"
}

@test "${ch_tag}/revert image" {
    unpack_img_all_nodes "$ch_cray"
}
