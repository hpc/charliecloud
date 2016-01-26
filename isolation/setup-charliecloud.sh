#!/bin/sh

set -e

PATH=$(dirname $0)/../bin:$PATH
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

ch-docker2tar $USER/chtest $WORKDIR
ch-tar2img $WORKDIR/$USER.chtest.tar.gz
ch-tar2img --no-scan $WORKDIR/$USER.chtest.tar.gz
