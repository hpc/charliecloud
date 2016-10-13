#!/bin/bash

# Run in directory where the tarball is.
# Output will go to same place.

TAG=mpibench-1.6.5
IMAGE=/tmp/$TAG

if [[ ! -e $IMAGE ]]; then
    mpirun -pernode ch-tar2dir ./$USER.$TAG.tar.gz $IMAGE
fi

time mpirun ch-run $IMAGE /usr/local/src/imb/src/IMB-MPI1 sendrecv \
    > imb-sendrecv-charlie.txt

time mpirun ch-run $IMAGE /usr/local/src/imb/src/IMB-MPI1 alltoall \
    > imb-alltoall-charlie.txt
