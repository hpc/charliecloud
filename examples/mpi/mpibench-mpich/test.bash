setup_specific () {
    prerequisites_ok mpibench-mpich
    crayify_mpi_maybe "$ch_img"
}
