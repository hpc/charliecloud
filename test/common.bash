sanity () {
    if ( bash -c 'set -e; [[ 1 = 0 ]]; exit 0' ); then
        # Bash bug: [[ ... ]] expression doesn't exit with set -e
        # https://github.com/sstephenson/bats/issues/49
        echo "Need at least Bash 4.1 for these tests." >&2
        exit 1
    fi
    for var in CH_TEST_WORKDIR; do
        if [[ -z ${!var} ]]; then
            echo "\$$var is empty or not set" >&2
            exit 1
        fi
    done
}

sanity_permdirs () {
    for var in CH_TEST_PERMDIRS; do
        if [[ -z ${!var} ]]; then
            echo "\$$var is empty or not set" >&2
           exit 1
        fi
    done
}

docker_ok () {
    sudo docker images | fgrep -q $1
}

image_ok () {
    test -d $1
    test -f $1/WEIRD_AL_YANKOVIC
    [[ -n $(du -s -t 4M $1) ]]  # image is non-trivial size?
}

tarball_ok () {
    test -f $1
    test -s $1
}

# Do we have what we need?
sanity

# Set path to the right Charliecloud.
CH_BIN="$(cd "$(dirname ${BASH_SOURCE[0]})/../bin" && pwd)"
PATH=$CH_BIN:$PATH

# Make separate directories for tarballs and images
TARDIR=$CH_TEST_WORKDIR/tarballs
IMGDIR=$CH_TEST_WORKDIR/images
mkdir -p $TARDIR
mkdir -p $IMGDIR

# Test directories to bind-mount
mkdir -p $IMGDIR/bind1
touch $IMGDIR/bind1/file1
mkdir -p $IMGDIR/bind2
touch $IMGDIR/bind2/file2

# Some test variables
EXAMPLE_TAG=$(basename $BATS_TEST_DIRNAME)
EXAMPLE_IMG=$IMGDIR/$EXAMPLE_TAG
CHTEST_TARBALL=$TARDIR/chtest.tar.gz
CHTEST_IMG=$IMGDIR/chtest
if [[ -n $GUEST_USER && -z $BATS_TEST_NAME ]]; then
    GUEST_UID=$(id -u $GUEST_USER)
    GUEST_GID=$(getent group $GUEST_GROUP | cut -d: -f3)
fi
