load ../../../test/common

setup() {
    scope full
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
