true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope full
    prerequisites_ok paraview
    indir=${CHTEST_EXAMPLES_DIR}/paraview
    outdir=$BATS_TMPDIR
    inbind=${indir}:/mnt/0
    outbind=${outdir}:/mnt/1
    if [[ $ch_multinode ]]; then
        # Bats only creates $BATS_TMPDIR on the first node.
        # shellcheck disable=SC2086
        $ch_mpirun_node mkdir -p "$BATS_TMPDIR"
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
#         rendered serially or using 2 or n processes.
#
# We do not check .pvtp (and its companion .vtp) output because it's a
# collection of XML files containing binary data and it seems too hairy to me.

@test "${ch_tag}/crayify image" {
    crayify_mpi_or_skip "$ch_img"
}

@test "${ch_tag}/cone serial" {
    [[ -z $ch_cray ]] || skip 'serial launches unsupported on Cray'
    # shellcheck disable=SC2086
    ch-run $ch_unslurm -b "$inbind" -b "$outbind" "$ch_img" -- \
           pvbatch /mnt/0/cone.py /mnt/1
    mv "$outdir"/cone.png "$outdir"/cone.serial.png
    ls -l "$outdir"/cone*
    diff -u "${indir}/cone.serial.vtk" "${outdir}/cone.vtk"
}

@test "${ch_tag}/cone serial PNG" {
    pict_ok
    pict_assert_equal "${indir}/cone.png" "${outdir}/cone.serial.png" 100
}

@test "${ch_tag}/cone ranks=2" {
    multiprocess_ok
    # shellcheck disable=SC2086
    $ch_mpirun_2 ch-run --join -b "$inbind" -b "$outbind" "$ch_img" -- \
              pvbatch /mnt/0/cone.py /mnt/1
    mv "$outdir"/cone.png "$outdir"/cone.2ranks.png
    ls -l "$outdir"/cone*
    diff -u "${indir}/cone.2ranks.vtk" "${outdir}/cone.vtk"
}

@test "${ch_tag}/cone ranks=2 PNG" {
    multiprocess_ok
    pict_ok
    pict_assert_equal "${indir}/cone.png" "${outdir}/cone.2ranks.png" 100
}

@test "${ch_tag}/cone ranks=N" {
    multiprocess_ok
    # shellcheck disable=SC2086
    $ch_mpirun_core ch-run --join -b "$inbind" -b "$outbind" "$ch_img" -- \
                 pvbatch /mnt/0/cone.py /mnt/1
    mv "$outdir"/cone.png "$outdir"/cone.nranks.png
    ls -l "$outdir"/cone*
    diff -u "${indir}/cone.nranks.vtk" "${outdir}/cone.vtk"
}

@test "${ch_tag}/cone ranks=N PNG" {
    multiprocess_ok
    pict_ok
    pict_assert_equal "${indir}/cone.png" "${outdir}/cone.nranks.png" 100
}

@test "${ch_tag}/revert image" {
    unpack_img_all_nodes "$ch_cray"
}
