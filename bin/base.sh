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

# pipe view is only useful when using an interactive terminal
if ( [ -t 1 ] && command -v pv >/dev/null 2>&1 ); then
    PV() {
        pv "$@"
    }
else
   PV() {
       # ignore all agruments, so that PV() is just a pass-through and does nothing
       cat
   }
fi
