#!/bin/bash

# Warning: This script installs software and messes with your "docker" binary.
# Don't run it unless you know what you are doing.

# We start in the Charliecloud Git working directory.

set -e
PREFIX=/var/tmp

# Remove sbin directories from $PATH (see issue #43). Assume none are first.
echo "$PATH"
for i in /sbin /usr/sbin /usr/local/sbin; do
    export PATH=${PATH/:$i/}
done
echo "$PATH"

set -x

case $TARBALL in
    export)
        (cd doc-src && make)
        make export
        mv charliecloud-*.tar.gz "$PREFIX"
        cd "$PREFIX"
        tar xf charliecloud-*.tar.gz
        cd charliecloud-*
        ;;
    export-bats)
        (cd doc-src && make)
        make export-bats
        mv charliecloud-*.tar.gz "$PREFIX"
        cd "$PREFIX"
        tar xf charliecloud-*.tar.gz
        cd charliecloud-*
        ;;
    archive)
        # The Travis image already has Bats installed.
        git archive HEAD --prefix=charliecloud/ -o "$PREFIX/charliecloud.tar"
        cd "$PREFIX"
        tar xf charliecloud.tar
        cd charliecloud
        ;;
esac

make
bin/ch-run --version

if [[ $INSTALL ]]; then
    sudo make install PREFIX="$PREFIX"
    cd "$PREFIX/libexec/charliecloud"
fi

cd test

make where-bats
make test

# To test without Docker, move the binary out of the way.
DOCKER=$(command -v docker)
sudo mv "$DOCKER" "$DOCKER.tmp"

make test

# For Travis, this isn't really necessary, since the VM will go away
# immediately after this script exits. However, restore the binary to enable
# testing this script in other environments.
sudo mv "$DOCKER.tmp" "$DOCKER"
