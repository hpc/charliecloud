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

@test "$EXAMPLE_TAG/installpackages" {
    # Note that this command actually installs multiple packages.
    # Before attempting to install openmpi, Spack will check
    # dependencies and automatically install any missing packages.
    # As such, this test installs libsigsegv, m4, libtool, util-macros,
    # libpciaccess, xz, libxml2, readline, gdbm, perl, autoconf, automake,
    # numactl, hwloc, and openmpi 3.0.1 
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c ". $SPACK_ENV && ./spack install openmpi"
}

@test "$EXAMPLE_TAG/clean" {
    # revert image back to orginal
    ch-tar2dir $TARDIR/spack.tar.gz $IMGDIR
}
