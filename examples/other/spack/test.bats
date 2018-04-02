load ../../../test/common

setup() {
    prerequisites_ok spack
    SPACK_IMG=$IMGDIR/spack
    SPACK_BIN=/spack/bin
}

clean() {
    # revert image back to orginal
    ch-tar2dir $TARDIR/spack.tar.gz $SPACK_IMG
}

@test "$EXAMPLE_TAG/basic" {
    # run basic usage from spack documentation
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c "./spack list"
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c "./spack info mpich"
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c "./spack versions libelf"  
}

@test "$EXAMPLE_TAG/install" {
    # install test packages
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c "./spack install subversion"
    # install a specific package version
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c "./spack install paraview@5.4.0"
}

@test "$EXAMPLE_TAG/find" {
    # confirm package install
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c "./spack find subversion"
    ch-run -w --no-home -c $SPACK_BIN $SPACK_IMG -- bash -c "./spack find paraview@5.4.0" 
}

@test "$EXAMPLE_TAG/clean" {
    clean
}
