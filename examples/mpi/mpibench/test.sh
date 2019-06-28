#!/bin/bash

set -e
cd "$(dirname "$0")"

chbase=$(dirname "$0")/../..
chbin=${chbase}/bin
outdir=/tmp
outtag=$(date -u +'%Y%m%dT%H%M%SZ')
imb=/usr/local/src/imb/src/IMB-MPI1

if [[ "$1" == build ]]; then
    shift
    "${chbin}/ch-build" -t "${USER}/mpibench" "$chbase"
    "${chbin}/ch-builder2tar" "${USER}/mpibench" /tmp
    "${chbin}/ch-tar2dir" "/tmp/${USER}.mpibench.tar.gz" /tmp/mpibench
fi

if [[ -n "$1" ]]; then

    echo "testing on host"
    time mpirun -n "$1" "$imb" \
         > "${outdir}/mpibench.host.${outtag}.txt"

    echo "testing in container"
    time mpirun -n "$1" "${chbin}/ch-run" /tmp/mpibench -- "$imb" \
         > "${outdir}/mpibench.guest.${outtag}.txt"

    echo "done; output in ${outdir}"
fi
