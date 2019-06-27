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
version=$(cat VERSION.full)

if [[ $INSTALL ]]; then
    sudo make install PREFIX="$PREFIX"
    cd "$PREFIX/libexec/charliecloud-$version"
fi

if [[ $SUDO_RM_FIRST ]]; then
    sudo rm /etc/sudoers.d/travis
fi
sudo -v || true

cd test

make where-bats
make test-build

if [[ $SUDO_RM_AFTER_BUILD ]]; then
    sudo rm /etc/sudoers.d/travis
fi
if [[ $SUDO_AVOID_AFTER_BUILD ]]; then
    export CH_TEST_DONT_SUDO=yes
fi
sudo -v || true
echo "\$CH_TEST_DONT_SUDO=$CH_TEST_DONT_SUDO"

make test-run
make test-test
