#!/bin/bash

set -e
cd $(dirname $0)

CHBIN=$(dirname $0)/../../bin

if [[ $1 == build ]]; then
    shift
    $CHBIN/docker-build -t $USER/mpihello .
    $CHBIN/ch-docker2tar $USER/mpihello /tmp
    $CHBIN/ch-tar2dir /tmp/$USER.mpihello.tar.gz /tmp/mpihello
fi

if [[ -n $1 ]]; then
    printf 'parent userns '
    stat -L --format='%i' /proc/self/ns/user
    mpirun -n $1 $CHBIN/ch-run /tmp/mpihello /hello/hello
fi
