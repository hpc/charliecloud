docker_ok () {
    sudo docker images | fgrep -q $1
}

env_require () {
    if [[ -z ${!1} ]]; then
        printf "\$$1 is empty or not set\n\n" >&2
        exit 1
    fi
}

image_ok () {
    ls -ld $1 $1/WEIRD_AL_YANKOVIC || true
    test -d $1
    ls -ld $1 || true
    byte_ct=$(du -s -B1 $1 | cut -f1)
    echo "$byte_ct"
    [[ $byte_ct -ge 4194304 ]]  # image is at least 4MB
}

tarball_ok () {
    ls -ld $1 || true
    test -f $1
    test -s $1
}

# Predictable sorting and collation
export LC_ALL=C

# Set path to the right Charliecloud.
CH_BIN="$(cd "$(dirname ${BASH_SOURCE[0]})/bin" && pwd)"
CH_BIN="$(readlink -f "$CH_BIN")"
PATH=$CH_BIN:$PATH

# Separate directories for tarballs and images
TARDIR=$CH_TEST_TARDIR
IMGDIR=$CH_TEST_IMGDIR

# Some test variables
EXAMPLE_TAG=$(basename $BATS_TEST_DIRNAME)
EXAMPLE_IMG=$IMGDIR/$EXAMPLE_TAG
CHTEST_TARBALL=$TARDIR/chtest.tar.gz
CHTEST_IMG=$IMGDIR/chtest
if [[ -n $GUEST_USER && -z $BATS_TEST_NAME ]]; then
    GUEST_UID=$(id -u $GUEST_USER)
    GUEST_GID=$(getent group $GUEST_GROUP | cut -d: -f3)
fi
CHTEST_MULTINODE=$SLURM_JOB_ID
if [[ $CHTEST_MULTINODE ]]; then
    # $SLURM_NTASKS isn't always set
    CHTEST_CORES=$(($SLURM_CPUS_ON_NODE * $SLURM_JOB_NUM_NODES))
fi

# Do we have what we need?
if ( bash -c 'set -e; [[ 1 = 0 ]]; exit 0' ); then
    # Bash bug: [[ ... ]] expression doesn't exit with set -e
    # https://github.com/sstephenson/bats/issues/49
    printf "Need at least Bash 4.1 for these tests.\n\n" >&2
    exit 1
fi
if [[ ! -x $CH_BIN/ch-run ]]; then
    printf 'Must build with "make" before running tests.\n\n' >&2
    exit 1
fi
env_require CH_TEST_TARDIR
env_require CH_TEST_IMGDIR
env_require CH_TEST_PERMDIRS
