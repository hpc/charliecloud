#!/bin/bash
#SBATCH --time=0:10:00

# Arguments: Path to tarball, path to image parent directory.

set -e

tar=$1
imgdir=$2
img=${2}/$(basename "${tar%.tar.gz}")

if [[ -z $tar ]]; then
    echo 'no tarball specified' 1>&2
    exit 1
fi
printf 'tarball:   %s\n' "$tar"

if [[ -z $imgdir ]]; then
    echo 'no image directory specified' 1>&2
    exit 1
fi
printf 'image:     %s\n' "$img"

# Make Charliecloud available (varies by site).
module purge
module load friendly-testing
module load charliecloud

# Unpack image.
srun ch-convert -o dir "$tar" "$imgdir"

# MPI version in container.
printf 'container: '
ch-run "$img" -- mpirun --version | grep -E '^mpirun'

# Run the app.
srun --cpus-per-task=1 ch-run "$img" -- /hello/hello
