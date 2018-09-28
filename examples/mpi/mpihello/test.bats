load ../../../test/common
load ./test

# Note: This file is common for both mpihello flavors. Flavor-specific setup
# is in test.bash.

count_ranks () {
      echo "$1" \
    | grep -E '^0: init ok' \
    | tail -1 \
    | sed -r 's/^.+ ([0-9]+) ranks.+$/\1/'
}

@test "${ch_tag}/serial" {
    # This seems to start up the MPI infrastructure (daemons, etc.) within the
    # guest even though there's no mpirun.
    run ch-run "$ch_img" -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *' 1 ranks'* ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}

@test "${ch_tag}/guest starts ranks" {
    # shellcheck disable=SC2086
    run ch-run "$ch_img" -- mpirun $ch_mpirun_np /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(count_ranks "$output")
    echo "found ${rank_ct} ranks, expected ${ch_cores_node}"
    [[ $rank_ct -eq "$ch_cores_node" ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}

@test "${ch_tag}/host starts ranks" {
    multiprocess_ok
    echo "starting ranks with: ${mpirun_core}"

    guest_mpi=$(ch-run "$ch_img" -- mpirun --version | head -1)
    echo "guest MPI: ${guest_mpi}"

    # shellcheck disable=SC2086
    run $ch_mpirun_core ch-run --join "$ch_img" -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(count_ranks "$output")
    echo "found ${rank_ct} ranks, expected ${ch_cores_total}"
    [[ $rank_ct -eq "$ch_cores_total" ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}
