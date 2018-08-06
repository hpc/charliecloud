load ../../../test/common

setup() {
    scope full
    [[ -z $CHTEST_CRAY ]] || skip 'issue #193 and Spack issue #8618'
    prerequisites_ok spack
    SPACK_IMG="$IMGDIR/spack"
    export PATH=/spack/bin:$PATH
}

@test "$EXAMPLE_TAG/version" {
    ch-run "$SPACK_IMG" -- spack --version
}

@test "$EXAMPLE_TAG/compilers" {
    echo "spack compiler list"
    ch-run "$SPACK_IMG" -- spack compiler list
    echo "spack compiler list --scope=system"
    ch-run "$SPACK_IMG" -- spack compiler list --scope=system
    echo "spack compiler list --scope=user"
    ch-run "$SPACK_IMG" -- spack compiler list --scope=user
    echo "spack compilers"
    ch-run "$SPACK_IMG" -- spack compilers
}

@test "$EXAMPLE_TAG/spec" {
    ch-run "$SPACK_IMG" -- spack spec netcdf
}
