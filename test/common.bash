arch_exclude () {
    if [[ $1 = "$(uname -m)" ]]; then
        skip "unsupported architecture: $(uname -m)"
    fi
}

builder_exclude () {
    if [[ $1 = "$CH_BUILDER" ]]; then
        skip "unsupported builder: $CH_BUILDER"
    fi
}

builder_tag_p () {
    printf 'image tag %s ... ' "$1"
    case $CH_BUILDER in
        ch-grow)
            if [[ -d ${CH_GROW_STORAGE}/img/${1} ]]; then
                echo "ok"
                return 0
            fi
            ;;
        docker)
            hash_=$(sudo docker images -q "$1" | sort -u)
            if [[ $hash_ ]]; then
                echo "$hash_"
                return 0
            fi
            ;;
    esac
    echo 'not found'
    return 1
}

builder_ok () {
    # FIXME: Currently we make fairly limited tagging for some builders.
    # Uncomment below when they can be supported by all the builders.
    #docker_tag_p "$1"
    builder_tag_p "${1}:latest"
    #docker_tag_p "${1}:$(ch-run --version |& tr '~+' '--')"
}

crayify_mpi_or_skip () {
    if [[ $ch_cray ]]; then
        # shellcheck disable=SC2086
        $ch_mpirun_node ch-fromhost --cray-mpi "$1"
    else
        skip 'host is not a Cray'
    fi
}

env_require () {
    if [[ -z ${!1} ]]; then
        printf '$%s is empty or not set\n\n' "$1" >&2
        exit 1
    fi
}

image_ok () {
    ls -ld "$1" "${1}/WEIRD_AL_YANKOVIC" || true
    test -d "$1"
    ls -ld "$1" || true
    byte_ct=$(du -s -B1 "$1" | cut -f1)
    echo "$byte_ct"
    [[ $byte_ct -ge 3145728 ]]  # image is at least 3MiB
}

multiprocess_ok () {
    [[ $ch_multiprocess ]] || skip 'no multiprocess launch tool found'
    # If the MPI in the container is MPICH, we only try host launch on Crays.
    # For the other settings (workstation, other Linux clusters), it may or
    # may not work; we simply haven't tried.
    [[ $ch_mpi = mpich && -z $ch_cray ]] \
        && skip 'MPICH untested'
    # Exit function successfully.
    true
}

need_docker () {
    # Skip test if $CH_BUILDER is not Docker. If argument provided, use that
    # tag as missing prerequisite sentinel file.
    pq=${ch_tardir}/${1}.pq_missing
    if [[ $pq ]]; then
        rm -f "$pq"
    fi
    if [[ $CH_BUILDER != docker ]]; then
        if [[ $pq ]]; then
            touch "$pq"
        fi
        skip 'requires Docker'
    fi
}

prerequisites_ok () {
    if [[ -f $CH_TEST_TARDIR/${1}.pq_missing ]]; then
        skip 'build prerequisites not met'
    fi
}

need_squashfs () {
    ( command -v mksquashfs >/dev/null 2>&1 ) || skip "no squashfs-tools found"
    ( command -v squashfuse >/dev/null 2>&1 ) || skip "no squashfuse found"
}

squashfs_ready () {
    ( command -v mksquashfs && command -v squashfuse )
}

scope () {
    case $1 in  # $1 is the test's scope
        quick)
            ;;  # always run quick-scope tests
        standard)
            if [[ $CH_TEST_SCOPE = quick ]]; then
                skip "${1} scope"
            fi
            ;;
        full)
            if [[ $CH_TEST_SCOPE = quick || $CH_TEST_SCOPE = standard ]]; then
                skip "${1} scope"
            fi
            ;;
        skip)
            skip "developer-skipped; see comments and/or issues"
            ;;
        *)
            exit 1
    esac
}

archive_ok () {
    ls -ld "$1" || true
    test -f "$1"
    test -s "$1"
}

unpack_img_all_nodes () {
    if [[ $1 ]]; then
        $ch_mpirun_node ch-tar2dir "${ch_tardir}/${ch_tag}.tar.gz" "$ch_imgdir"
    else
        skip 'not needed'
    fi
}

archive_grep () {
    image="$1"
    case $image in
        *.sqfs)
            unsquashfs -l "$image" | grep 'squashfs-root/ch/environment'
            ;;
        *)
            tar -tf "$image" | grep -E '^(\./)?ch/environment$'
            ;;
    esac
}

# Predictable sorting and collation
export LC_ALL=C

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

# Set path to the right Charliecloud. This uses a symlink in this directory
# called "bin" which points to the corresponding bin directory, either simply
# up and over (source code) or set during "make install".
#
# Note that sudo resets $PATH, so if you want to run any Charliecloud stuff
# under sudo, you must use an absolute path.
ch_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/bin" && pwd)"
ch_bin="$(readlink -f "${ch_bin}")"
export PATH=$ch_bin:$PATH
# shellcheck disable=SC2034
ch_runfile=$(command -v ch-run)
# shellcheck disable=SC2034
ch_libexec=$(ch-build --libexec-path)
if [[ ! -x ${ch_bin}/ch-run ]]; then
    printf 'Must build with "make" before running tests.\n\n' >&2
    exit 1
fi

# Tests require explicitly set builder.
if [[ -z $CH_BUILDER ]]; then
    CH_BUILDER=$(ch-build --print-builder)
    export CH_BUILDER
fi

# Charliecloud version.
ch_version=$(ch-run --version 2>&1)
# shellcheck disable=SC2034
ch_version_docker=$(echo "$ch_version" | tr '~+' '--')

# Separate directories for tarballs and images.
#
# Canonicalize both so the have consistent paths and we can reliably use them
# in tests (see issue #143). We use readlink(1) rather than realpath(2),
# despite the admonition in the man page, because it's more portable [1].
#
# [1]: https://unix.stackexchange.com/a/136527
ch_imgdir=$(readlink -ef "$CH_TEST_IMGDIR")
ch_tardir=$(readlink -ef "$CH_TEST_TARDIR")
ch_mounts="${ch_imgdir}/mounts"
if [[ $CH_BUILDER = ch-grow ]]; then
    export CH_GROW_STORAGE=$ch_tardir/_ch-grow
fi

# Image information.
ch_tag=${CH_TEST_TAG:-NO_TAG_SET}  # set by Makefile; many tests don't need it
ch_img=${ch_imgdir}/${ch_tag}
ch_tar=${ch_tardir}/${ch_tag}.tar.gz
ch_ttar=${ch_tardir}/chtest.tar.gz
ch_timg=${ch_imgdir}/chtest

# User-private temporary directory in case multiple users are running the
# tests simultaneously.
btnew=$BATS_TMPDIR/bats.tmp.$USER
mkdir -p "$btnew"
chmod 700 "$btnew"
export BATS_TMPDIR=$btnew
[[ $(stat -c %a "$BATS_TMPDIR") = '700' ]]

# MPICH requires different handling from OpenMPI. Set a variable to enable
# some kludges.
if [[ $ch_tag = *'-mpich' ]]; then
    ch_mpi=mpich
    # First kludge. MPICH's internal launcher is called "Hydra". If Hydra sees
    # Slurm environment variables, it tries to launch even local ranks with
    # "srun". This of course fails within the container. You can't turn it off
    # by building with --without-slurm like OpenMPI, so we fall back to this
    # environment variable at run time.
    export HYDRA_LAUNCHER=fork
else
    ch_mpi=openmpi
fi

# Crays are special.
if [[ -f /etc/opt/cray/release/cle-release ]]; then
    ch_cray=yes
else
    ch_cray=
fi

# Slurm stuff.
if [[ $SLURM_JOB_ID ]]; then
    ch_nodes=$SLURM_JOB_NUM_NODES
else
    ch_nodes=1
fi
# One rank per hyperthread can exhaust hardware contexts, resulting in
# communication failure. Use one rank per core to avoid this. There are ways
# to do this with Slurm, but they need Slurm configuration that seems
# unreliably present. This seems to be the most portable way to do this.
ch_cores_node=$(lscpu -p | tail -n +5 | sort -u -t, -k 2 | wc -l)
ch_cores_total=$((ch_nodes * ch_cores_node))
ch_mpirun_np="-np ${ch_cores_node}"
ch_unslurm=
if [[ $SLURM_JOB_ID ]]; then
    ch_multinode=yes     # can run on multiple nodes
    ch_multiprocess=yes  # can run multiple processes
    ch_mpirun_node='srun --ntasks-per-node 1'               # 1 rank/node
    ch_mpirun_core="srun --ntasks-per-node $ch_cores_node"  # 1 rank/core
    ch_mpirun_2='srun -n2'                                  # 2 ranks, 2 nodes
    ch_mpirun_2_1node='srun -N1 -n2'                        # 2 ranks, 1 node
    # OpenMPI 3.1 pukes when guest-launched and Slurm environment variables
    # are present. Work around this by fooling OpenMPI into believing it's not
    # in a Slurm allocation.
    if [[ $ch_mpi = openmpi ]]; then
        ch_unslurm='--unset-env=SLURM*'
    fi
else
    ch_multinode=
    if ( command -v mpirun >/dev/null 2>&1 ); then
        ch_multiprocess=yes
        ch_mpirun_node='mpirun --map-by ppr:1:node'
        ch_mpirun_core="mpirun ${ch_mpirun_np}"
        ch_mpirun_2='mpirun -np 2'
        ch_mpirun_2_1node='mpirun -np 2'
    else
        ch_multiprocess=
        ch_mpirun_node=''
        ch_mpirun_core=false
        ch_mpirun_2=false
        ch_mpirun_2_1node=false
    fi
fi

# If the variable CH_TEST_SKIP_DOCKER is true, we skip all the tests that
# depend on Docker. It's true if user-set or command "docker" is not in $PATH.
if ( ! command -v docker >/dev/null 2>&1 ); then
    CH_TEST_SKIP_DOCKER=yes
fi

# Validate CH_TEST_SCOPE and set if empty.
if [[ -z $CH_TEST_SCOPE ]]; then
    CH_TEST_SCOPE=standard
elif [[    $CH_TEST_SCOPE != quick \
        && $CH_TEST_SCOPE != standard \
        && $CH_TEST_SCOPE != full ]]; then
    # shellcheck disable=SC2016
    printf '$CH_TEST_SCOPE value "%s" is invalid\n\n' "$CH_TEST_SCOPE" >&2
    exit 1
fi

# Do we have and want sudo?
if    [[ -z $CH_TEST_DONT_SUDO ]] \
   && ( command -v sudo >/dev/null 2>&1 && sudo -v >/dev/null 2>&1 ); then
    # This isn't super reliable; it returns true if we have *any* sudo
    # privileges, not specifically to run the commands we want to run.
    # shellcheck disable=SC2034
    ch_have_sudo=yes
fi
