load ../../../test/common

setup() {
    scope full
    skip 'issue #204 and Spack issue #8673'
    [[ -z $CHTEST_CRAY ]] || skip 'issue #193 and Spack issue #8618'
    prerequisites_ok spack
    SPACK_IMG=$IMGDIR/spack
    export PATH=/spack/bin:$PATH
}

@test "$EXAMPLE_TAG/version" {
    ch-run $SPACK_IMG -- spack --version
}

@test "$EXAMPLE_TAG/compilers" {
    ch-run $SPACK_IMG -- spack compilers
}

@test "$EXAMPLE_TAG/spec" {
    ch-run $SPACK_IMG -- spack spec netcdf
}
