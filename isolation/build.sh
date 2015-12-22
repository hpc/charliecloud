#!/bin/bash

cd $(dirname $0)
echo "building in $PWD"

# Build the image.
sudo docker build -t $USER/chtest \
                  --build-arg HTTP_PROXY=$HTTP_PROXY \
                  --build-arg HTTPS_PROXY=$HTTPS_PROXY \
                  --build-arg http_proxy=$http_proxy \
                  --build-arg https_proxy=$https_proxy \
                  --build-arg no_proxy=$no_proxy \
                  .
