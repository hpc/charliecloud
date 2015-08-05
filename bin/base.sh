# Do we need sudo to run docker?
if ( docker info > /dev/null 2>&1 ); then
    export DOCKER="docker"
else
    export DOCKER="sudo docker"
fi
