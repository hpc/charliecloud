#!/bin/bash

cd $(dirname $0)
echo "building in $PWD"

rm -Rf data
mkdir data

# Find root device major and minor numbers.
# FIXME: what about lustre, NFS mounts?
#rootdev=$(mount | fgrep 'on / ' | cut -d' ' -f1)
#if [[ $rootdev =~ /dev ]]; then
#    stat -c '%t' $rootdev > data/rootmajor_hex
#    stat -c '%T' $rootdev > data/rootminor_hex
#fi

# Find IP non-loopback addresses.
#mkdir data/ips
#for addr in $(hostname --all-ip-addresses); do
#    touch data/ips/$addr
#done

# Build the image.
sudo docker build -q -t $USER/chtest \
                  --build-arg HTTP_PROXY=$HTTP_PROXY \
                  --build-arg HTTPS_PROXY=$HTTPS_PROXY \
                  --build-arg http_proxy=$http_proxy \
                  --build-arg https_proxy=$https_proxy \
                  --build-arg no_proxy=$no_proxy \
                  .
