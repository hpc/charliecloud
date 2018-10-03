load ../../../test/common

setup() {
    scope full
    [[ -z $ch_cray ]] || skip 'issue #193 and Spack issue #8618'
    prerequisites_ok spack
    export PATH=/spack/bin:$PATH
}

@test "${ch_tag}/version" {
    ch-run "$ch_img" -- spack --version
}

@test "${ch_tag}/compilers" {
    echo "spack compiler list"
    ch-run "$ch_img" -- spack compiler list
    echo "spack compiler list --scope=system"
    ch-run "$ch_img" -- spack compiler list --scope=system
    echo "spack compiler list --scope=user"
    ch-run "$ch_img" -- spack compiler list --scope=user
    echo "spack compilers"
    ch-run "$ch_img" -- spack compilers
}

@test "${ch_tag}/spec" {
    ch-run "$ch_img" -- spack spec netcdf
}
