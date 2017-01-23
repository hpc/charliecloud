#!/bin/bash

set -e
cd $(dirname $0)

CHBASE=$(dirname $0)/../..
CHBIN=$CHBASE/bin
OUTDIR=/tmp
OUTTAG=$(date -u +'%Y%m%dT%H%M%SZ')
IMB=/usr/local/src/imb/src/IMB-MPI1

if [[ $1 == build ]]; then
    shift
    $CHBIN/ch-build -t $USER/mpibench $CHBASE
    $CHBIN/ch-docker2tar $USER/mpibench /tmp
    $CHBIN/ch-tar2dir /tmp/$USER.mpibench.tar.gz /tmp/mpibench
fi

if [[ -n $1 ]]; then

    echo "testing on host"
    time mpirun -n $1 $IMB \
         > $OUTDIR/mpibench.host.$OUTTAG.txt

    echo "testing in container"
    time mpirun -n $1 $CHBIN/ch-run /tmp/mpibench -- $IMB \
         > $OUTDIR/mpibench.guest.$OUTTAG.txt

    echo "done; output in $OUTDIR"
fi
