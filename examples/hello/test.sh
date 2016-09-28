#!/bin/sh

set -e

cd $(dirname $0)
. ./util.sh

export PATH=../../bin:$PATH

if [ -n $1 ]; then
    WORKDIR=$1
else
    echo "No workdir specified" 1>&2
    exit 1
fi

TAG=$USER/hello
TAGDOT=$(echo $TAG | sed 's/\//./g')
TARBALL=$WORKDIR/$TAGDOT.tar.gz
IMAGE=$WORKDIR/$TAGDOT

case $2 in
    build)
        BUILD=yes
        ;;
    run)
        RUN=yes
        ;;
    '')
        BUILD=yes
        RUN=yes
        ;;
    *)
        echo "Unknown command" 1>&2
        exit 1
        ;;
esac

echo "workdir: $WORKDIR"
echo "build:   ${BUILD:-no}"
echo "run:     ${RUN:-no}"

if [ $BUILD ]; then
    docker-build -t $TAG .
    ch-docker2tar $TAG $WORKDIR
fi

if [ $RUN ]; then
    if [ -e $TARBALL ]; then
        echo "found tarball $TARBALL"
    else
        echo "tarball $TARBALL does not exist" 1>&2
        exit 1
    fi
    echo "unpacking in $IMAGE"
    ch-tar2dir $TARBALL $IMAGE
    echo
    echo 'host info:'
    print_info
    echo
    echo 'running container'
    echo
    ch-run -d . $IMAGE /mnt/0/hello.sh
fi
