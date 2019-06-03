#!/bin/bash
#SBATCH --time=0:10:00

# Arguments: Path to tarball, path to image parent directory.

set -e

tar=$1
imgdir=$2
img=${2}/$(basename "${tar%.tar.gz}")

fatal () {
    printf '%s\n\n' "$1" 2>&1
    exit 1
}

[[ -n $tar ]] || fatal'no tarball specified'
printf 'tarball:   %s\n' "$tar"

[[ -n $imgdir ]] || fatal 'no image directory specified'
printf 'image:     %s\n' "$img"

# Make Charliecloud available (varies by site).
module purge
module load friendly-testing
module load charliecloud

# Unpack image.
srun ch-tar2dir "$tar" "$imgdir"

# MPI version in container.
printf 'container: '
ch-run "$img" -- mpirun --version | grep -E '^mpirun'

# Run the app.
srun --cpus-per-task=1 ch-run "$img" -- /hello/hello
