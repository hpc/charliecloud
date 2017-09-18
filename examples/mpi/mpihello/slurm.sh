#!/bin/bash
#SBATCH --time=0:10:00

# Arguments: Path to tarball, path to image parent directory.

set -e

TAR="$1"
IMGDIR="$2"
IMG="$2/$(basename "${TAR%.tar.gz}")"

if [[ -z $TAR ]]; then
    echo 'no tarball specified' 1>&2
    exit 1
fi
printf 'tarball:   %s\n' "$TAR"

if [[ -z $IMGDIR ]]; then
    echo 'no image directory specified' 1>&2
    exit 1
fi
printf 'image:     %s\n' "$IMG"

# Make Charliecloud available (varies by site).
module purge
module load openmpi
module load sandbox
module load charliecloud

# Makes "mpirun -pernode" work.
export OMPI_MCA_rmaps_base_mapping_policy=

# MPI version on host.
printf 'host:      '
mpirun --version | egrep '^mpirun'

# Unpack image.
mpirun -pernode ch-tar2dir $TAR $IMGDIR

# MPI version in container.
printf 'container: '
ch-run $IMG -- mpirun --version | egrep '^mpirun'

# Run the app.
mpirun ch-run $IMG -- /hello/hello
