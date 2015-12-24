#!/bin/bash

cd $(dirname $0)
CUSER=''

while getopts 'u:' opt; do
    case $opt in
        u)
            CUSER="-u $OPTARG" ;;
    esac
done
shift $((OPTIND-1))

for i in $(seq $#); do
    pt[$i]="-v ${!i}/perms_test/pass:/$i"
done

DATADIR=$(./setup.sh)
echo "# standard error in $DATADIR/err"

sudo docker run $CUSER -v /dev:/dev -v /etc/passwd:/etc/passwd -v $DATADIR:/0 ${pt[@]} $USER/chtest /test/test.sh
