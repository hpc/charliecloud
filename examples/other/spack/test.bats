load ../../../test/common

setup() {
    scope full
    prerequisites_ok spack
    SPACK_IMG=$IMGDIR/spack
    SPACK_BIN=/spack/bin
    SPACK_ENV=/spack/share/spack/setup-env.sh
}

@test "$EXAMPLE_TAG/unittests" {
    # Run Spack unit tests
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c ". $SPACK_ENV && ./spack test"
}

@test "$EXAMPLE_TAG/installpackage" {
    # Install a small package 
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c ". $SPACK_ENV && ./spack install libsigsegv"
}

@test "$EXAMPLE_TAG/clean" {
    # revert image back to orginal
    ch-tar2dir $TARDIR/spack.tar.gz $IMGDIR
}
