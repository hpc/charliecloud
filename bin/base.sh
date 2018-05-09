CH_BIN="$(cd "$(dirname "$0")" && pwd)"

LIBEXEC="$(cd "$(dirname "$0")" && pwd)"
. ${LIBEXEC}/version.sh

# Do we need sudo to run docker?
if ( docker info > /dev/null 2>&1 ); then
    export DOCKER="docker"
else
    export DOCKER="sudo docker"
fi

# Use parallel gzip if it's available. ("command -v" is POSIX.1-2008.)
if ( command -v pigz >/dev/null 2>&1 ); then
    export GZIP_CMD=pigz
else
    export GZIP_CMD=gzip
fi

# Use pv to show a progress bar, if it's available. (We also don't want a
# progress bar if stdin is not a terminal, but pv takes care of that.)
if ( command -v pv >/dev/null 2>&1 ); then
    PV() {
        pv -pteb "$@"
    }
else
    PV() {
        # Arguments may be present, but we ignore them.
        cat
    }
fi
