#!/bin/bash

set -e
cd $(dirname $0)

CHBASE=$(dirname $0)/../..
CHBIN=$CHBASE/bin
TAG=mpibench-1.6.5
OUTDIR=/tmp
OUTTAG=$(date -u +'%Y%m%dT%H%M%SZ')
IMB=/usr/local/src/imb/src/IMB-MPI1

if [[ $1 == build ]]; then
    shift
    $CHBIN/docker-build -t $USER/mpibench-1.6.5 $CHBASE
    $CHBIN/ch-docker2tar $USER/mpibench-1.6.5 /tmp
    $CHBIN/ch-tar2dir /tmp/$USER.mpibench-1.6.5.tar.gz /tmp/mpibench-1.6.5
fi

if [[ -n $1 ]]; then

    echo "testing on host"
    time mpirun -n $1 $IMB \
         > $OUTDIR/mpibench-1.6.5.host.$OUTTAG.txt

    echo "testing in container"
    time mpirun -n $1 $CHBIN/ch-run /tmp/mpibench-1.6.5 -- $IMB \
         > $OUTDIR/mpibench-1.6.5.guest.$OUTTAG.txt

    echo "done; output in $OUTDIR"
fi
