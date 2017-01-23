CH_BIN="$(cd "$(dirname "$0")" && pwd)"

. "$CH_BIN/version.sh"

# Do we need sudo to run docker?
if ( docker info > /dev/null 2>&1 ); then
    export DOCKER="docker"
else
    export DOCKER="sudo docker"
fi
