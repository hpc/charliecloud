#!/bin/bash

# The three isolation layers; all enabled by default. -i argument selects just
# one to test.
I_FILESCAN=yes
I_MOUNT=yes
I_USER=yes

# Do we drop privileges?
DROP_PRIVS=yes

set -e
#set -x

cd $(dirname $0)
CHBIN=$(dirname $0)/../bin

while getopts 'i:uv' opt; do
    case $opt in
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
                *)
                    echo "Unknown isolation layer '$OPTARG'" 1>&2
                    exit 1
                    ;;
            esac
            ;;
        u)
            DROP_PRIVS=
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

for i in $(seq $#); do
    pt[$i]="${!i}/perms_test/pass"
done

DATADIR=$(./preamble.sh)
echo "# standard error in $DATADIR/err"

echo "# isolation:"
echo "#   file scan:        ${I_FILESCAN:-no}"
echo "#   safe mount:       ${I_MOUNT:-no}"
echo "#   user namespace:   ${I_USER:-no}"
echo "#   drop privileges:  ${DROP_PRIVS:-no}"

OUT=${OUT:-$DATADIR/err/setup-teardown.err}

printf '# mounting image: '
if [[ ! $I_FILESCAN ]]; then
    IMG=$(echo -n "$IMG" | sed -r 's/\.img$/.NOSCAN.img/')
fi
if [[ ! $I_MOUNT ]]; then
    MOUNTARG=--unsafe
fi
echo "$IMG $UNSAFE_ARG"
sudo $CHBIN/ch-mount $MOUNTARG "$IMG" $DATADIR ${pt[@]} >> $OUT 2>&1

printf '# running test: '
if [[ ! $I_USER ]]; then
    # FIXME
    #RUNARG=--no-user-ns
    true
fi
CHRUN=$CHBIN/ch-run.ns
if [[ ! $DROP_PRIVS ]]; then
    CHRUN="sudo ${CHRUN}.unsafe"
fi
echo "$CHRUN"
$CHRUN /test/test.sh

echo "# unmounting image"
sudo $CHBIN/ch-umount >> $OUT 2>&1

echo "# test completed; stderr in $DATADIR/err"
