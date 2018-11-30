load ../../../test/common

setup () {
    scope full
    gpu_ok
    source_script='source docker-env.sh'
}

gpu_ok {
    command -v nvidia-container-cli > /dev/null 2>&1 \
        || skip 'nvidia-container-cli not in PATH'

    command nvidia-container-cli list --binaries --libraries > /dev/null 2>&1 \
        || skip 'cuda capable device undetected'
}

@test "${ch_tag}/fromhost --nvidia" {
    gpu_ok
    $ch-fromhost --nvidia -v "$ch_img"
    [[ $status -eq 0 ]]
}

@test "${ch_tag}/pilot3 p3b1 benchmark" {
    gpu_ok
    run_benchmark='python /opt/Benchmarks/Pilot3/P3B1/p3b1_baseline_keras2.py'
    ch-run -w "$ch_img" -- /bin/bash -c "$source_script && $run_benchmark"
    [[ $status -eq 0 ]]
}

@test "${ch_tag}/supervisor workflow" {
    gpu_ok
    run_workflow='./opt/Tutorials/2018/NIH/Supervisor/workflow.sh -x01'
    ch-run -w "$ch_img" -- /bin/bash -c "$source_script && $run_workflow"
    [[ $status -eq 0 ]]
}

@test "${ch_tag}/revert image" {
    ch-tar2dir "$ch_tar" "${ch_img%/*}"
}
