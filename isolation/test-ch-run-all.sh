#!/bin/bash

# Isolation test driver for multiple variations of ch-run options.
#
# Correct operation depends on permission test directories being set up with
# "you" being "nobody".
#
# We do not use any of the -i options. Because ch-run is a pure user-mode
# program with no privileges, the user can select any in-container UID and GID
# s/he likes. Thus, the file scan and safe mount options, which protect
# against escalation, are moot.

IMAGE=$1
OUTDIR=$2
shift 2

set -e

if [[ $# -lt 1 ]]; then
    echo 'not enough args' 1>&2
    exit 1
fi

IHOME=$(readlink -f $(dirname $0))

mkdir -p $OUTDIR
cd $OUTDIR

GID=$(id -g)

for cuid in $UID 0 65534; do
    for cgid in $GID 0 65534; do
        $IHOME/test-ch-run.sh -u$cuid -g$cgid $IMAGE "$@" | tee out.$cuid-$cgid
        if [[ ! -d test ]]; then
            echo 'no test directory found' 1>&2
            exit 1
        fi
        mv test test.$cuid-$cgid
    done
done
