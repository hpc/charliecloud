load ../../../test/common

setup () {
    scope full
    nvidia-cli_ok
    arg0='source docker-env.sh'
}

nvidia-cli_ok () {
    command -v nvidia-container-cli >/dev/null 2>&1 \
        || skip 'nvidia-container-cli not in PATH'
}

@test "${ch_tag}/fromhost --nvidia" {
    ch-fromhost --nvidia -v "$ch_img"
    [[ $status -eq 0 ]]
}

@test "${ch_tag}/pilot3 p3b1 benchmark" {
    arg1='python /opt/Benchmarks/Pilot3/P3B1/p3b1_baseline_keras2.py'
    ch-run -w "$ch_img" -- /bin/bash -c "$arg0 && $arg1"
    [[ $status -eq 0 ]]
}

@test "${ch_tag}/supervisor workflow" {
    arg1='./opt/Tutorials/2018/NIH/Supervisor/workflow.sh -x01'
    ch-run -w "$ch_img" -- /bin/bash -c "$arg0 && $arg1"
    [[ $status -eq 0 ]]
}

@test "${ch_tag}/revert image" {
    ch-tar2dir "$ch_tar" "${ch_img%/*}"
}
