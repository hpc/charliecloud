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
module load friendly-testing
module load charliecloud

# Unpack image.
srun ch-tar2dir "$TAR" "$IMGDIR"

# MPI version in container.
printf 'container: '
ch-run "$IMG" -- mpirun --version | grep -E '^mpirun'

# Run the app.
srun --cpus-per-task=1 ch-run "$IMG" -- /hello/hello
