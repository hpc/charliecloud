#!/bin/bash

set -e
set -x

echo "INSTALL=$INSTALL EXPORT=$EXPORT SETUID=$SETUID"

if [[ $EXPORT ]]; then
    make export
    tar xf charliecloud-*.tar.gz
    rm charliecloud-*.tar.gz
    cd charliecloud-*
fi

# We start in the Charliecloud Git working directory, so no cd needed.
make SETUID=$SETUID

if [[ $INSTALL ]]; then
    sudo make install PREFIX=/usr/local
    cd /usr/local/share/doc/charliecloud
fi

cd test
make test-quick
make test-all
