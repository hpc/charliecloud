#!/bin/bash

set -e
cd $(dirname $0)

CHBASE=$(dirname $0)/../..
CHBIN=$CHBASE/bin

if [[ $1 == build ]]; then
    shift
    $CHBIN/docker-build -t $USER/mpihello $CHBASE
    $CHBIN/ch-docker2tar $USER/mpihello /tmp
    $CHBIN/ch-tar2dir /tmp/$USER.mpihello.tar.gz /tmp/mpihello
fi

if [[ -n $1 ]]; then
    printf 'parent userns '
    stat -L --format='%i' /proc/self/ns/user
    $CHBIN/ch-run /tmp/mpihello -- mpirun --nolocal -d -n $1 /hello/hello
fi
