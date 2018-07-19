load ../../../test/common

setup () {
    scope full
    prerequisites_ok paraview
    IMG=$IMGDIR/paraview
    INDIR=$BATS_TEST_DIRNAME
    OUTDIR=$BATS_TMPDIR
    if [[ $CHTEST_MULTINODE ]]; then
        # Bats only creates $BATS_TMPDIR on the first node.
        $MPIRUN_NODE mkdir -p $BATS_TMPDIR
    fi
}

# The first two tests demonstrate ParaView as an "executable" to process a
# non-containerized input deck (cone.py) and produce non-containerized output.
#
#   .png: In previous versions, PNG output is antialiased with a single rank
#         and not with multiple ranks depending on the execution environment.
#	  This is no longer the case as of version 5.5.4 but may change with
#   	  a new version of Paraview.
#
#   .vtk: The number of extra and/or duplicate points and indexing of these
#         points into polygons varied by rank count on my VM, but not on the
#         cluster. The resulting VTK file is dependent on whether an image was 
# 	  rendered serially or using 2 or n processes.
#
# We do not check .pvtp (and its companion .vtp) output because it's a
# collection of XML files containing binary data and it seems too hairy to me.

@test "$EXAMPLE_TAG/cone serial" {
    ch-run -b $INDIR -b $OUTDIR $IMG -- \
           pvbatch /mnt/0/cone.py /mnt/1
    ls -l $OUTDIR/cone*
    diff -u $INDIR/cone.serial.vtk $OUTDIR/cone.vtk
    cmp $INDIR/cone.png $OUTDIR/cone.png
}

@test "$EXAMPLE_TAG/cone ranks=2" {
    multiprocess_ok
    $MPIRUN_2 ch-run --join -b $INDIR -b $OUTDIR $IMG -- \
              pvbatch /mnt/0/cone.py /mnt/1
    ls -l $OUTDIR/cone*
       diff -u $INDIR/cone.2ranks.vtk $OUTDIR/cone.vtk
       cmp $INDIR/cone.png $OUTDIR/cone.png
}

@test "$EXAMPLE_TAG/cone ranks=N" {
    multiprocess_ok
    $MPIRUN_CORE ch-run --join -b $INDIR -b $OUTDIR $IMG -- \
                 pvbatch /mnt/0/cone.py /mnt/1
    ls -l $OUTDIR/cone*
       diff -u $INDIR/cone.nranks.vtk $OUTDIR/cone.vtk
       cmp $INDIR/cone.png $OUTDIR/cone.png
}
