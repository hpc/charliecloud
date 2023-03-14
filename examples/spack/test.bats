true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup() {
    scope full
    prerequisites_ok spack
    export PATH=/spack/bin:$PATH
}

@test "${ch_tag}/version" {
    # Spack likes to write to $HOME/.spack; thus, we bind it.
    ch-run --home "$ch_img" -- spack --version
}

@test "${ch_tag}/compilers" {
    echo "spack compiler list"
    ch-run --home "$ch_img" -- spack compiler list
    echo "spack compiler list --scope=system"
    ch-run --home "$ch_img" -- spack compiler list --scope=system
    echo "spack compiler list --scope=user"
    ch-run --home "$ch_img" -- spack compiler list --scope=user
    echo "spack compilers"
    ch-run --home "$ch_img" -- spack compilers
}

@test "${ch_tag}/find" {
    run ch-run --home "$ch_img" -- spack find charliecloud
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud@'* ]]
}
