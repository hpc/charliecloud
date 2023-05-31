CH_TEST_TAG=$ch_test_tag
load "${CHTEST_DIR}/common.bash"

setup () {
    scope full
    prerequisites_ok "$ch_tag"
    pmix_or_skip
    if [[ $srun_mpi != pmix* ]]; then
        skip 'pmix required'
    fi
}

count_ranks () {
      echo "$1" \
    | grep -E '^0: init ok' \
    | tail -1 \
    | sed -r 's/^.+ ([0-9]+) ranks.+$/\1/'
}

@test "${ch_tag}/guest starts ranks" {
    openmpi_or_skip
    # shellcheck disable=SC2086
    run ch-run $ch_unslurm "$ch_img" -- mpirun $ch_mpirun_np /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(count_ranks "$output")
    echo "found ${rank_ct} ranks, expected ${ch_cores_node}"
    [[ $rank_ct -eq "$ch_cores_node" ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}

@test "${ch_tag}/inject cray mpi ($cray_prov)" {
    cray_ofi_or_skip "$ch_img"
    run ch-run "$ch_img" -- fi_info
    echo "$output"
    [[ $output == *"provider: $cray_prov"* ]]
    [[ $output == *"fabric: $cray_prov"* ]]
    [[ $status -eq 0 ]]
}

@test "${ch_tag}/validate $cray_prov injection" {
    [[ -n "$ch_cray" ]] || skip "host is not cray"
    [[ -n "$CH_TEST_OFI_PATH" ]] || skip "--fi-provider not set"
    run $ch_mpirun_node ch-run --join "$ch_img" -- sh -c \
                    "FI_PROVIDER=$cray_prov FI_LOG_LEVEL=info /hello/hello 2>&1"
    echo "$output"
    [[ $status -eq 0 ]]
    if [[ "$cray_prov" == gni ]]; then
        [[ "$output" == *' registering provider: gni'* ]]
        [[ "$output" == *'gni:'*'gnix_ep_nic_init()'*'Allocated new NIC for EP'* ]]
    fi
    if [[ "$cray_prov" == cxi ]]; then
        [[ "$output" == *'cxi:mr:ofi_'*'stats:'*'searches'*'deletes'*'hits'* ]]
    fi
}

@test "${ch_tag}/MPI version" {
    [[ -z $ch_cray ]] || skip 'serial launches unsupported on Cray'
    # shellcheck disable=SC2086
    run ch-run $ch_unslurm "$ch_img" -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    if [[ $ch_mpi = openmpi ]]; then
        [[ $output = *'Open MPI'* ]]
    else
        [[ $ch_mpi = mpich ]]
        if [[ $ch_cray ]]; then
            [[ $output = *'CRAY MPICH'* ]]
        else
            [[ $output = *'MPICH Version:'* ]]
        fi
    fi
}

@test "${ch_tag}/empty stderr" {
   multiprocess_ok
   output=$($ch_mpirun_core ch-run --join "$ch_img" -- \
                            /hello/hello 2>&1 1>/dev/null)
   echo "$output"
   [[ -z "$output" ]]
}

@test "${ch_tag}/serial" {
    [[ -z $ch_cray ]] || skip 'serial launches unsupported on Cray'
    # This seems to start up the MPI infrastructure (daemons, etc.) within the
    # guest even though there's no mpirun.
    # shellcheck disable=SC2086
    run ch-run $ch_unslurm "$ch_img" -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *' 1 ranks'* ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}

@test "${ch_tag}/host starts ranks" {
    multiprocess_ok
    echo "starting ranks with: ${ch_mpirun_core}"

    guest_mpi=$(ch-run "$ch_img" -- mpirun --version | head -1)
    echo "guest MPI: ${guest_mpi}"

    # shellcheck disable=SC2086
    run $ch_mpirun_core ch-run --join "$ch_img" -- /hello/hello 2>&1
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(count_ranks "$output")
    echo "found ${rank_ct} ranks, expected ${ch_cores_total}"
    [[ $rank_ct -eq "$ch_cores_total" ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}

@test "${ch_tag}/Cray bind mounts" {
    [[ $ch_cray ]] || skip 'host is not a Cray'

    ch-run "$ch_img" -- mount | grep -F /dev/hugepages
    if [[ $cray_prov == 'gni' ]]; then
        ch-run "$ch_img" -- mount | grep -F /var/opt/cray/alps/spool
    else
        ch-run "$ch_img" -- mount | grep -F /var/spool/slurmd
    fi
}

@test "${ch_tag}/revert image" {
    unpack_img_all_nodes "$ch_cray"
}
