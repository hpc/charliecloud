#!/bin/bash

# The three isolation layers; all enabled by default. -i argument selects just
# one to test.
I_FILESCAN=yes
I_MOUNT=yes
I_USER=yes

# IDs to use inside container
CUID=$UID
CGID=$(id -g $UID)

set -e
#set -x

CHBIN=$(dirname $0)/../bin

while getopts 'g:i:u:v' opt; do
    case $opt in
        g)
            CGID=$OPTARG
            ;;
        i)  # less isolation
            case $OPTARG in
                F)
                    I_FILESCAN=yes
                    I_MOUNT=
                    I_USER=
                    ;;
                M)
                    I_FILESCAN=
                    I_MOUNT=yes
                    I_USER=
                    ;;
                U)
                    I_FILESCAN=
                    I_MOUNT=
                    I_USER=yes
                    ;;
                X)
                    I_FILESCAN=
                    I_MOUNT=
                    I_USER=
                    ;;
                *)
                    echo "Unknown isolation layer '$OPTARG'" 1>&2
                    exit 1
                    ;;
            esac
            ;;
        u)
            CUID=$OPTARG
            ;;
        v)  # setup/teardown output to terminal, not files
            OUT=/dev/fd/2
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
    pt[$i]="$dir"
done

DATADIR=$($(dirname $0)/preamble.sh)
echo "# standard error in $DATADIR/err"

echo "# isolation:"
echo "#   container UID:    $CUID"
echo "#   container GID:    $CGID"
echo "#   file scan:        ${I_FILESCAN:-no}"
echo "#   safe mount:       ${I_MOUNT:-no}"
echo "#   user namespace:   ${I_USER:-no}"

OUT=${OUT:-$DATADIR/err/setup-teardown.err}

printf '# mounting image: '
if [[ ! $I_FILESCAN ]]; then
    IMG=$(echo -n "$IMG" | sed -r 's/\.img$/.NOSCAN.img/')
fi
if [[ ! $I_MOUNT ]]; then
    MOUNTARG=--unsafe
fi
echo "$IMG $UNSAFE_ARG"
sudo $CHBIN/ch-mount $MOUNTARG "$IMG" $DATADIR ${pt[@]} >> "$OUT" 2>&1

printf '# running test: '
if [[ ! $I_USER ]]; then
    RUNARG=--no-userns
    true
fi
CHRUN="$CHBIN/ch-run -u $CUID -g $CGID $RUNARG /test/test.sh"
echo "$CHRUN"
$CHRUN

echo "# unmounting image"
sudo $CHBIN/ch-umount >> $OUT 2>&1

echo "# test completed; stderr in $DATADIR/err"
