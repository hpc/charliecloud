#!/bin/bash

function usage () {
    cat 1>&2 <<EOF
Run container isolation tests with ch-run.

Usage:

  $ $(basename $0) [-g GID] [-h] [-u UID] [-z] NEWROOT OUTDIR [PDIR1 [PDIR2] ...]

Options:

  -g GID  Use group GID inside the container
  -u UID  Use user UID inside the container
  -z      Don't isolate with user namespace

TESTDIR is used for test scratch space and output.

PDIRn are perms_test directories created with make-perms-test.

EOF
    exit 1
}

# If true, turn on the user namespace
I_USERNS=yes

# IDs to use inside container
CUID=$UID
CGID=$(id -g $UID)

set -e
#set -x

CHBIN=$(dirname $0)/../bin

while getopts 'g:hu:z' opt; do
    case $opt in
        g)
            CGID=$OPTARG
            ;;
        h)
            usage
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

if [[ $# -lt 2 ]]; then
    usage
fi
IMG="$1"
TESTDIR="$2"
shift 2

echo
echo '### test-ch-run.sh starting'

for i in $(seq $#); do
    dir="${!i}/pass"
    if [[ ! -d $dir ]]; then
        echo "$dir: not a directory" 1>&2
        exit 1
    fi
    BINDS[$i]="-d $dir"
done

$(dirname $0)/preamble.sh "$TESTDIR"
echo "# standard error in $TESTDIR/err"

echo "# isolation:"
echo "#   container UID:    $CUID"
echo "#   container GID:    $CGID"
echo "#   user namespace:   ${I_USER:-no}"

printf '# running test: '
if [[ ! $I_USERNS ]]; then
    RUNARG=--no-userns
    true
fi
CHRUN="$CHBIN/ch-run -u $CUID -g $CGID -d $TESTDIR ${BINDS[@]} $RUNARG $IMG /test/test.sh"
echo "$CHRUN"
$CHRUN

echo "# test completed; stderr in $TESTDIR/err"
