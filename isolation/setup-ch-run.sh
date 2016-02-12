#!/bin/sh

set -e

CHROOT=$(dirname $0)/../bin
WORKDIR=$1
if [ -z "$USER" -o "$USER" = root ]; then
    echo 'Who are you?' 1>&2
    exit 1
fi
if [ -z "$WORKDIR" ]; then
    echo 'No image directory specified' 1>&2
    exit 1
fi

echo "Docker repository: $USER"
echo "Image directory:   $WORKDIR"

$CHROOT/ch-docker2tar $USER/chtest $WORKDIR
sudo $CHROOT/ch-tar2img $WORKDIR/$USER.chtest.tar.gz $WORKDIR
sudo $CHROOT/ch-tar2img --no-scan $WORKDIR/$USER.chtest.tar.gz $WORKDIR
