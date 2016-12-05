#!/bin/bash

# Run in directory where the tarball is.
# Output will go to same place.

# MSUB -l walltime=0:10:00

set -e

TAG=mpihello
IMAGE=/tmp/$TAG

printf 'host:      '
mpirun --version | egrep '^mpirun'

if [[ ! -e $IMAGE ]]; then
    mpirun -pernode ch-tar2dir ./$TAG.tar.gz $IMAGE > /dev/null
fi

printf 'container: '
ch-run $IMAGE -- mpirun --version | egrep '^mpirun'

mpirun ch-run $IMAGE -- /hello/hello
