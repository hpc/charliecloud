#!/bin/bash

# Warning: This script installs software and messes with your "docker" binary.
# Don't run it unless you know what you are doing.

# We start in the Charliecloud Git working directory.

set -e

# Remove sbin directories from $PATH (see issue #43). Assume none are first.
echo $PATH
for i in /sbin /usr/sbin /usr/local/sbin; do
    export PATH=${PATH/:$i/}
done
echo $PATH

set -x

case $TARBALL in
    export)
        (cd doc-src && make)
        make export
        tar xf charliecloud-*.tar.gz
        cd charliecloud-*
        ;;
    archive)
        # The Travis image already has Bats installed.
        git archive HEAD --prefix=charliecloud/ -o charliecloud.tar
        tar xf charliecloud.tar
        cd charliecloud
        ;;
esac

if [[ $PKG_BUILD ]]; then
    for i in packaging/*/travis.sh; do $i; done
    # FIXME: If we continue with the rest of the tests after building the
    # packages, they hang in "make test-all", I believe in test "ch-build
    # python3" but I have not been able to verify this.
    exit
fi

make
bin/ch-run --version

if [[ $INSTALL ]]; then
    sudo make install PREFIX=/usr/local
    cd /usr/local/share/doc/charliecloud
fi

cd test

make where-bats
make test

# To test without Docker, move the binary out of the way.
DOCKER=$(which docker)
sudo mv $DOCKER $DOCKER.tmp

make test

# For Travis, this isn't really necessary, since the VM will go away
# immediately after this script exits. However, restore the binary to enable
# testing this script in other environments.
sudo mv $DOCKER.tmp $DOCKER
