#!/bin/bash

# If true, turn on the user namespace
I_USERNS=yes

# IDs to use inside container
CUID=$UID
CGID=$(id -g $UID)

set -e
#set -x

CHBIN=$(dirname $0)/../bin

while getopts 'g:u:z' opt; do
    case $opt in
        g)
            CGID=$OPTARG
            ;;
        u)
            CUID=$OPTARG
            ;;
        z)
            I_USERNS=
            ;;
    esac
done
shift $((OPTIND-1))

if [[ $# -lt 1 ]]; then
    echo 'no image specified' 1>&2
    exit 1
fi
IMG="$1"
shift

echo
echo '### test-ch-run.sh starting'

for i in $(seq $#); do
    dir="${!i}/perms_test/pass"
    if [[ ! -d $dir ]]; then
        echo "$dir: not a directory" 1>&2
        exit 1
    fi
    BINDS[$i]="-d $dir"
done

DATADIR=$($(dirname $0)/preamble.sh)
echo "# standard error in $DATADIR/err"

echo "# isolation:"
echo "#   container UID:    $CUID"
echo "#   container GID:    $CGID"
echo "#   file scan:        ${I_FILESCAN:-no}"
echo "#   safe mount:       ${I_MOUNT:-no}"
echo "#   user namespace:   ${I_USER:-no}"

printf '# running test: '
if [[ ! $I_USERNS ]]; then
    RUNARG=--no-userns
    true
fi
CHRUN="$CHBIN/ch-run -u $CUID -g $CGID -d $DATADIR ${BINDS[@]} $RUNARG $IMG /test/test.sh"
echo "$CHRUN"
$CHRUN

echo "# test completed; stderr in $DATADIR/err"
