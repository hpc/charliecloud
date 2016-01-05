#!/bin/bash

cd $(dirname $0)

ARGS=''
while getopts 'pu:' opt; do
    case $opt in
        p)
            ARGS+=' --privileged --cap-add=ALL'
            ;;
        u)
            ARGS+=" -u $OPTARG"
            ;;
    esac
done
shift $((OPTIND-1))

for i in $(seq $#); do
    pt[$i]="-v ${!i}/perms_test/pass:/$i"
done

DATADIR=$(./setup.sh)
echo "# standard error in $DATADIR/err"

sudo docker run $ARGS -v /dev:/dev -v /etc/passwd:/etc/passwd -v $DATADIR:/0 ${pt[@]} $USER/chtest /test/test.sh
