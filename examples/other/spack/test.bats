load ../../../test/common

setup() {
    prerequisites_ok spack
    SPACK_IMG=$IMGDIR/spack
    SPACK_ROOT=/spack
}

clean() {
    # revert image back to orginal
    ch-tar2dir $TARDIR/spack.tar.gz $SPACK_IMG
}

@test "$EXAMPLE_TAG/basic" {
    # run basic usage from spack documentation
    ch-run -w --no-home $SPACK_IMG -- bash -c "export PATH=$SPACK_ROOT/bin:$PATH && spack list"
    ch-run -w --no-home $SPACK_IMG -- bash -c "export PATH=$SPACK_ROOT/bin:$PATH && spack info mpich"
    ch-run -w --no-home $SPACK_IMG -- bash -c "export PATH=$SPACK_ROOT/bin:$PATH && spack versions libelf"  
}

@test "$EXAMPLE_TAG/install" {
    # install a package
    ch-run -w --no-home $SPACK_IMG -- bash -c "export PATH=$SPACK_ROOT/bin:$PATH && spack install mpileaks" 
}

@test "$EXAMPLE_TAG/clean" {
    clean
}
