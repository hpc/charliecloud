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

# Do we have what we need?
sanity

# Set path to the right Charliecloud.
CH_BIN="$(cd "$(dirname ${BASH_SOURCE[0]})/../bin" && pwd)"
PATH=$CH_BIN:$PATH

# Separate directories for tarballs and images
TARDIR=$CH_TEST_WORKDIR/tarballs
IMGDIR=$CH_TEST_WORKDIR/images

# Some test variables
EXAMPLE_TAG=$(basename $BATS_TEST_DIRNAME)
EXAMPLE_IMG=$IMGDIR/$EXAMPLE_TAG
CHTEST_TARBALL=$TARDIR/chtest.tar.gz
CHTEST_IMG=$IMGDIR/chtest
if [[ -n $GUEST_USER && -z $BATS_TEST_NAME ]]; then
    GUEST_UID=$(id -u $GUEST_USER)
    GUEST_GID=$(getent group $GUEST_GROUP | cut -d: -f3)
fi
