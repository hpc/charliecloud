load ../../../test/common

setup () {
    scope full
    gpu_ok
}

gpu_ok () {
    command -v nvidia-container-cli > /dev/null 2>&1 \
        || skip 'nvidia-container-cli not in PATH'

    command nvidia-container-cli list --binaries --libraries > /dev/null 2>&1 \
        || skip 'cuda capable device undetected'
}

@test "${ch_tag}/fromhost --nvidia" {
    ch-fromhost --nvidia -v "$ch_img"
}

@test "${ch_tag}/pilot3 p3b1 benchmark" {
    ch-run --set-env="${ch_img}/environment" -w "$ch_img" -- python /opt/Benchmarks/Pilot3/P3B1/p3b1_baseline_keras2.py
}

@test "${ch_tag}/supervisor workflow" {
    ch-run --set-env="${ch_img}/environment" -w "$ch_img" -- ./opt/Tutorials/2018/NIH/Supervisor/workflow.sh -x01
}
