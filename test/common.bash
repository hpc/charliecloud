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
    [[ $byte_ct -ge 3145728 ]]  # image is at least 3MiB
}

need_docker () {
    # Skip test if $CH_TEST_SKIP_DOCKER is true. If argument provided, use
    # that tag as missing prerequisite sentinel file.
    PQ=$TARDIR/$1.pq_missing
    if [[ $PQ ]]; then
        rm -f $PQ
    fi
    if [[ $CH_TEST_SKIP_DOCKER ]]; then
        if [[ $PQ ]]; then
            touch $PQ
        fi
        skip 'Docker not found or user-skipped'
    fi
}

prerequisites_ok () {
    if [[ -f $TARDIR/$1.pq_missing ]]; then
        skip 'build prerequisites not met'
    fi
}

tarball_ok () {
    ls -ld $1 || true
    test -f $1
    test -s $1
}

# Predictable sorting and collation
export LC_ALL=C

# Set path to the right Charliecloud. This uses a symlink in this directory
# called "bin" which points to the corresponding bin directory, either simply
# up and over (source code) or set during "make install".
#
# Note that sudo resets $PATH, so if you want to run any Charliecloud stuff
# under sudo, you must use an absolute path.
CH_BIN="$(cd "$(dirname ${BASH_SOURCE[0]})/bin" && pwd)"
CH_BIN="$(readlink -f "$CH_BIN")"
export PATH=$CH_BIN:$PATH
CH_RUN_FILE="$(which ch-run)"
if [[ -u $CH_RUN_FILE ]]; then
    CH_RUN_SETUID=yes
fi

# User-private temporary directory in case multiple users are running the
# tests simultaenously.
btnew=$BATS_TMPDIR/bats.tmp.$USER
mkdir -p $btnew
chmod 700 $btnew
export BATS_TMPDIR=$btnew
[[ $(stat -c '%a' $BATS_TMPDIR) = '700' ]]

# Separate directories for tarballs and images
TARDIR=$CH_TEST_TARDIR
IMGDIR=$CH_TEST_IMGDIR

# Some test variables
EXAMPLE_TAG=$(basename $BATS_TEST_DIRNAME)
EXAMPLE_IMG=$IMGDIR/$EXAMPLE_TAG
CHTEST_TARBALL=$TARDIR/chtest.tar.gz
CHTEST_IMG=$IMGDIR/chtest
CHTEST_MULTINODE=$SLURM_JOB_ID
if [[ $CHTEST_MULTINODE ]]; then
    # $SLURM_NTASKS isn't always set, nor is $SLURM_CPUS_ON_NODE despite the
    # documentation.
    if [[ -z $SLURM_CPUS_ON_NODE ]]; then
        SLURM_CPUS_ON_NODE=$(echo $SLURM_JOB_CPUS_PER_NODE | cut -d'(' -f1)
    fi
    CHTEST_CORES=$(($SLURM_CPUS_ON_NODE * $SLURM_JOB_NUM_NODES))
fi

# If the variable CH_TEST_SKIP_DOCKER is true, we skip all the tests that
# depend on Docker. It's true if user-set or command "docker" is not in $PATH.
if ( ! command -v docker >/dev/null 2>&1 ); then
    CH_TEST_SKIP_DOCKER=yes
fi

# Do we have sudo?
if ( command -v sudo >/dev/null 2>&1 && sudo -v >/dev/null 2>&1 ); then
    # This isn't super reliable; it returns true if we have *any* sudo
    # privileges, not specifically to run the commands we want to run.
    CHTEST_HAVE_SUDO=yes
fi

# Do we have what we need?
env_require CH_TEST_TARDIR
env_require CH_TEST_IMGDIR
env_require CH_TEST_PERMDIRS
if ( bash -c 'set -e; [[ 1 = 0 ]]; exit 0' ); then
    # Bash bug: [[ ... ]] expression doesn't exit with set -e
    # https://github.com/sstephenson/bats/issues/49
    printf 'Need at least Bash 4.1 for these tests.\n\n' >&2
    exit 1
fi
if [[ ! -x $CH_BIN/ch-run ]]; then
    printf 'Must build with "make" before running tests.\n\n' >&2
    exit 1
fi
if ( mount | fgrep -q $IMGDIR ); then
    printf 'Something is mounted under %s.\n\n' $IMGDIR >&2
    exit 1
fi
