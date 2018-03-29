load ../../../test/common

setup () {
    scope full
    prerequisites_ok paraview
    IMG=$IMGDIR/paraview
    INDIR=$BATS_TEST_DIRNAME
    OUTDIR=$BATS_TMPDIR
}

# The first two tests demonstrate ParaView as an "executable" to process a
# non-containerized input deck (cone.py) and produce non-containerized output.
#
# Different numbers of nodes yield slightly different output:
#
#   .png: With a single node, PNG output is antialiased. With multiple nodes,
#         it is not. It was not obvious to me how to just turn off
#         antialiasing.
#
#   .vtk: The number of extra and/or duplicate points and indexing of these
#         points into polygons varies by node count.
#
# We do not check .pvtp (and its companion .vtp) output because it's a
# collection of XML files containing binary data and it seems too hairy to me.

@test "$EXAMPLE_TAG/cone serial" {
    ch-run -b $INDIR -b $OUTDIR $IMG -- \
           pvbatch /mnt/0/cone.py /mnt/1
    ls -l $OUTDIR/cone*
    diff -u $INDIR/cone.1.vtk $OUTDIR/cone.vtk
    cmp $INDIR/cone.smooth.png $OUTDIR/cone.png
}

@test "$EXAMPLE_TAG/cone ranks=2" {
    $MPIRUN_2 ch-run -b $INDIR -b $OUTDIR $IMG -- \
              pvbatch /mnt/0/cone.py /mnt/1
    ls -l $OUTDIR/cone*
    diff -u $INDIR/cone.2.vtk $OUTDIR/cone.vtk
    cmp $INDIR/cone.jagged.png $OUTDIR/cone.png
}

@test "$EXAMPLE_TAG/cone ranks=N" {
    $MPIRUN_CORE ch-run -b $INDIR -b $OUTDIR $IMG -- \
                 pvbatch /mnt/0/cone.py /mnt/1
    ls -l $OUTDIR/cone*
    cmp $INDIR/cone.jagged.png $OUTDIR/cone.png
}
