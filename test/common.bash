# shellcheck shell=bash

arch_exclude () {
    # Skip the test if architecture (from "uname -m") matches $1.
    [[ $(uname -m) != "$1" ]] || skip "arch ${1}"
}

archive_grep () {
    image="$1"
    case $image in
        *.sqfs)
            unsquashfs -l "$image" | grep 'squashfs-root/ch/environment'
            ;;
        *)
            tar -tf "$image" | grep -E '^([^/]*/)?ch/environment$'
            ;;
    esac
}

archive_ok () {
    ls -ld "$1" || true
    test -f "$1"
    test -s "$1"
}

build_ () {
    case $CH_TEST_BUILDER in
        ch-image)
            "$ch_bin"/ch-image build "$@"
            ;;
        docker)
            # Coordinate this list with test "build.bats/proxy variables".
            # shellcheck disable=SC2154
            docker_ build --build-arg HTTP_PROXY="$HTTP_PROXY" \
                          --build-arg HTTPS_PROXY="$HTTPS_PROXY" \
                          --build-arg NO_PROXY="$NO_PROXY" \
                          --build-arg http_proxy="$http_proxy" \
                          --build-arg https_proxy="$https_proxy" \
                          --build-arg no_proxy="$no_proxy" \
                          "$@"
            ;;
        *)
            printf 'invalid builder: %s\n' "$CH_TEST_BUILDER" >&2
            exit 1
            ;;
    esac
}

builder_ok () {
    # FIXME: Currently we make fairly limited tagging for some builders.
    # Uncomment below when they can be supported by all the builders.
    builder_tag_p "$1"
    #builder_tag_p "${1}:latest"
    #docker_tag_p "${1}:$(ch-run --version |& tr '~+' '--')"
}

builder_tag_p () {
    printf 'image tag %s ... ' "$1"
    case $CH_TEST_BUILDER in
        buildah*)
            hash_=$(buildah images -q "$1" | sort -u)
            if [[ $hash_ ]]; then
                echo "$hash_"
                return 0
            fi
            ;;
        ch-image)
            if [[ -d ${CH_IMAGE_STORAGE}/img/${1} ]]; then
                echo "ok"
                return 0
            fi
            ;;
        docker)
            hash_=$(docker_ images -q "$1" | sort -u)
            if [[ $hash_ ]]; then
                echo "$hash_"
                return 0
            fi
            ;;
    esac
    echo 'not found'
    return 1
}

chtest_fixtures_ok () {
    echo "checking chtest fixtures in: ${1}"
    # Did we raise hidden files correctly?
    [[ -e ${1}/.hiddenfile1 ]]
    [[ -e ${1}/..hiddenfile2 ]]
    [[ -e ${1}/...hiddenfile3 ]]
    # Did we remove the right /dev stuff?
    [[ -e ${1}/mnt/dev/dontdeleteme ]]
    ls -Aq "${1}/dev"
    [[ $(ls -Aq "${1}/dev") = '' ]]
    ch-run "$1" -- test -e /mnt/dev/dontdeleteme
    # Are permissions still good?
    ls -ld "$1"/maxperms_*
    [[ $(stat -c %a "${1}/maxperms_dir") = 1777 ]]
    [[ $(stat -c %a "${1}/maxperms_file") = 777 ]]
}

crayify_mpi_or_skip () {
    if [[ $ch_cray ]]; then
        # shellcheck disable=SC2086
        $ch_mpirun_node ch-fromhost --cray-mpi "$1"
    else
        skip 'host is not a Cray'
    fi
}

# Do we need sudo to run docker?
if docker info > /dev/null 2>&1; then
    docker_ () {
        docker "$@"
    }
else
    docker_ () {
        sudo docker "$@"
    }
fi

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

pedantic_fail () {
    msg=$1
    if [[ -n $ch_pedantic ]]; then
        echo "$msg" 1>&2
        return 1
    else
        skip "$msg"
    fi
}

# If the two images (graphics, not container) are not "almost equal", fail.
# The first argument is the reference image; the second is the test image. The
# third argument, if given, is the maximum number of differing pixels (default
# zero). Also produce a diff image, which highlights the differing pixels in
# red, based on the sample, e.g. foo.png -> foo.diff.png.
pict_assert_equal () {
    ref=$1
    sample=$2
    pixel_max_ct=${3:-0}
    sample_base=${sample%.*}
    sample_ext=${sample##*.}
    diff_=${sample_base}.diff.${sample_ext}
    echo "reference:   ${ref}"
    echo "sample:      ${sample}"
    echo "diff image:  ${diff_}"
    # See: https://imagemagick.org/script/command-line-options.php#metric
    pixel_ct=$(compare -metric AE "$ref" "$sample" "$diff_" 2>&1 || true)
    echo "diff count:  ${pixel_ct} pixels, max ${pixel_max_ct}"
    [[ $pixel_ct -le $pixel_max_ct ]]
}

# Check if the pict_ functions are usable; if not, pedantic-fail.
pict_ok () {
    if ! command -v compare > /dev/null 2>&1; then
        pedantic_fail 'need ImageMagick'
    fi
}

prerequisites_ok () {
    if [[ -f $CH_TEST_TARDIR/${1}.pq_missing ]]; then
        skip 'build prerequisites not met'
    fi
}

# Wrapper for Bats run() to work around Bats bug #89 by saving/restoring $IFS.
# See issues #552 and #555 and https://stackoverflow.com/a/32425874.
if type run &> /dev/null; then
    eval bats_"$(declare -f run)"
fi
run () {
    local ifs_old="$IFS"
    bats_run "$@"
    IFS="$ifs_old"
}

scope () {
    if [[ -n $ch_one_test ]]; then
        # Ignore scope if a single test is given.
        if [[ $BATS_TEST_DESCRIPTION != *"$ch_one_test"* ]]; then
            skip 'per --file'
        else
            return 0
        fi
    fi
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

unpack_img_all_nodes () {
    if [[ $1 ]]; then
        case $CH_TEST_PACK_FMT in
            squash-mount)
                # Lots of things expect no extension here, so go with that even
                # though it's a file, not a directory.
                $ch_mpirun_node ln -s "${ch_tardir}/${ch_tag}.sqfs" "${ch_imgdir}/${ch_tag}"
                ;;
            squash-unpack)
                $ch_mpirun_node ch-convert -o dir "${ch_tardir}/${ch_tag}.sqfs" "${ch_imgdir}/${ch_tag}"
                ;;
            tar-unpack)
                $ch_mpirun_node ch-convert -o dir "${ch_tardir}/${ch_tag}.tar.gz" "${ch_imgdir}/${ch_tag}"
                ;;
            *)
                false  # unknown format
                ;;
        esac
    else
        skip 'not needed'
    fi
}

# Do we have what we need?
env_require CH_TEST_TARDIR
env_require CH_TEST_IMGDIR
env_require CH_TEST_PERMDIRS
env_require CH_TEST_BUILDER
if [[ $CH_TEST_BUILDER == ch-image ]]; then
    env_require CH_IMAGE_STORAGE
fi

# User-private temporary directory in case multiple users are running the
# tests simultaneously.
# shellcheck disable=SC2154
btnew=$TMP_/bats.tmp
mkdir -p "$btnew"
chmod 700 "$btnew"
export BATS_TMPDIR=$btnew
[[ $(stat -c %a "$BATS_TMPDIR") = '700' ]]

# shellcheck disable=SC2034
ch_runfile=$(command -v ch-run)
# shellcheck disable=SC2034
ch_lib=$(ch-convert --_lib-path)

# Charliecloud version.
ch_version=$(ch-run --version 2>&1)
# shellcheck disable=SC2034
ch_version_base=$(echo "$ch_version" | sed -E 's/~.+//')
# shellcheck disable=SC2034
ch_version_docker=$(echo "$ch_version" | tr '~+' '--')

# Separate directories for tarballs and images.
#
# Canonicalize both so the have consistent paths and we can reliably use them
# in tests (see issue #143). We use readlink(1) rather than realpath(2),
# despite the admonition in the man page, because it's more portable [1].
#
# We use "readlink -m" rather than "-e" or "-f" to account for the possibility
# of some directory anywhere the path not existing [2], which has bitten us
# multiple times; see issues #347 and #733. With this switch, if something is
# missing, readlink(1) returns the path unchanged, and checks later convert
# that to a proper error.
#
# [1]: https://unix.stackexchange.com/a/136527
# [2]: http://man7.org/linux/man-pages/man1/readlink.1.html
ch_imgdir=$(readlink -m "$CH_TEST_IMGDIR")
ch_tardir=$(readlink -m "$CH_TEST_TARDIR")
# shellcheck disable=SC2034
ch_mounts="${ch_imgdir}/mounts"

# Image information.
# shellcheck disable=SC2034
ch_tag=${CH_TEST_TAG:-NO_TAG_SET}  # set by Makefile; many tests don't need it
# shellcheck disable=SC2034
ch_img=${ch_imgdir}/${ch_tag}
# shellcheck disable=SC2034
ch_tar=${ch_tardir}/${ch_tag}.tar.gz
# shellcheck disable=SC2034
ch_ttar=${ch_tardir}/chtest.tar.gz
# shellcheck disable=SC2034
ch_timg=${ch_imgdir}/chtest

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

# Multi-node and multi-process stuff. Do not use Slurm variables in tests; use
# these instead:
#
#   ch_multiprocess    can run multiple processes
#   ch_multinode       can run on multiple nodes
#   ch_nodes           number of nodes in job
#   ch_cores_node      number of cores per node
#   ch_cores_total     total cores in job ($ch_nodes × $ch_cores_node)
#
#   ch_mpirun_node     command to run one rank per node
#   ch_mpirun_core     command to run one rank per physical core
#   ch_mpirun_2        command to run two ranks per job launcher default
#   ch_mpirun_2_1node  command to run two ranks on one node
#   ch_mpirun_2_2node  command to run two ranks on two nodes (one rank/node)
#
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
# shellcheck disable=SC2034
ch_cores_total=$((ch_nodes * ch_cores_node))
ch_mpirun_node=
ch_mpirun_np="-np ${ch_cores_node}"
# shellcheck disable=SC2034
ch_unslurm=
if [[ $SLURM_JOB_ID ]]; then
    ch_multiprocess=yes
    ch_mpirun_node='srun --ntasks-per-node 1'
    ch_mpirun_core="srun --ntasks-per-node $ch_cores_node"
    ch_mpirun_2='srun -n2'
    ch_mpirun_2_1node='srun -N1 -n2'
    # OpenMPI 3.1 pukes when guest-launched and Slurm environment variables
    # are present. Work around this by fooling OpenMPI into believing it's not
    # in a Slurm allocation.
    if [[ $ch_mpi = openmpi ]]; then
        # shellcheck disable=SC2034
        ch_unslurm='--unset-env=SLURM*'
    fi
    if [[ $ch_nodes -eq 1 ]]; then
        ch_multinode=
        ch_mpirun_2_2node=false
    else
        ch_multinode=yes
        ch_mpirun_2_2node='srun -N2 -n2'
    fi
else
    # shellcheck disable=SC2034
    ch_multinode=
    # shellcheck disable=SC2034
    ch_mpirun_2_2node=false
    if command -v mpirun > /dev/null 2>&1; then
        ch_multiprocess=yes
        ch_mpirun_node='mpirun --map-by ppr:1:node'
        ch_mpirun_core="mpirun ${ch_mpirun_np}"
        ch_mpirun_2='mpirun -np 2'
        ch_mpirun_2_1node='mpirun -np 2 --host localhost:2'
    else
        ch_multiprocess=
        ch_mpirun_node=''
        # shellcheck disable=SC2034
        ch_mpirun_core=false
        # shellcheck disable=SC2034
        ch_mpirun_2=false
        # shellcheck disable=SC2034
        ch_mpirun_2_1node=false
    fi
fi

# Do we have and want sudo?
if    [[ $CH_TEST_SUDO ]] \
   && command -v sudo >/dev/null 2>&1 \
   && sudo -v > /dev/null 2>&1; then
    # This isn't super reliable; it returns true if we have *any* sudo
    # privileges, not specifically to run the commands we want to run.
    # shellcheck disable=SC2034
    ch_have_sudo=yes
fi
