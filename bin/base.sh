set -e

# shellcheck disable=SC2034
ch_bin="$(cd "$(dirname "$0")" && pwd)"

libexec="$(cd "$(dirname "$0")" && pwd)"
. "${libexec}/version.sh"


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

# Use parallel gzip if it's available. ("command -v" is POSIX.1-2008.)
if ( command -v pigz >/dev/null 2>&1 ); then
    gzip_ () {
        pigz "$@"
    }
else
    gzip_ () {
        gzip "$@"
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
