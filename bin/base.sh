set -e

# shellcheck disable=SC2034
ch_bin="$(cd "$(dirname "$0")" && pwd)"

libexec="$(cd "$(dirname "$0")" && pwd)"
. "${libexec}/version.sh"


# Don't call in a subshell or the selection will be lost.
builder_choose () {
    if [ -z "$CH_BUILDER" ]; then
        if ( command -v docker >/dev/null 2>&1 ); then
            export CH_BUILDER=docker
        else
            export CH_BUILDER=ch-grow
        fi
    fi
    case $CH_BUILDER in
        buildah|buildah-runc|buildah-setuid|ch-grow|docker)
            ;;
        *)
            echo "unknown builder: $CH_BUILDER" 1>&2
            exit 1
            ;;
    esac
}

parse_basic_args () {
    for i in "$@"; do
        if [ "$i" = --help ]; then
            usage 0
        fi
        if [ "$i" = --libexec-path ]; then
            echo "$libexec"
            exit 0
        fi
        if [ "$1" = --version ]; then
            version
            exit 0
        fi
    done
}

# Set a charliecloud variable and print its value, human readable description,
# and origin.
# Parameter 1: string: name of the variable
# Parameter 2: string: human readable description
# Parameter 3: string: command line argument value
# Parameter 4: string: environment variable value
# Parameter 5: string: default value
set_chvar () {
    if   [ "$3" ]; then
         export "$1"="$3"
         value=$3
         method='command line'
    elif [ "$4" ]; then
         export "$1"="$4"
         value=$4
         method='environment variable'
    else
        export "$1"="$5"
        value=$5
        method='default'
    fi
    printf "setting %s to %s (%s)\n" "$2"  "$value" "$method"
}

# Convert container registry path to filesystem compatible path.
tag_to_path () {
    echo "$1" | sed 's/\//./g'
}

usage () {
    echo "${usage:?}" 1>&2
    exit "${1:-1}"
}

# Do we need sudo to run docker?
if ( docker info > /dev/null 2>&1 ); then
    docker_ () {
        docker "$@"
    }
else
    docker_ () {
        sudo docker "$@"
    }
fi

# Use parallel gzip if it's available.
if ( command -v pigz >/dev/null 2>&1 ); then
    gzip_ () {
        pigz "$@"
    }
else
    gzip_ () {
        gzip "$@"
    }
fi

# Use fuse low-level API if it's available.
if ( command -v squashfuse_ll >/dev/null 2>&1 ); then
    squashfuse_ () {
        squashfuse_ll "$@"
    }
else
    squashfuse_ () {
        echo "WARNING:" 1>&2
        echo "Low-level FUSE API unavailable; squashfuse will be slower" 1>&2
        squashfuse "$@"
    }
fi

# Use pv to show a progress bar, if it's available. (We also don't want a
# progress bar if stdin is not a terminal, but pv takes care of that.)
if ( command -v pv >/dev/null 2>&1 ); then
    pv_ () {
        pv -pteb "$@"
    }
else
    pv_ () {
        # Arguments may be present, but we ignore them.
        cat
    }
fi
