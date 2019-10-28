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
    archive)
        # The Travis image already has Bats installed.
        git archive HEAD --prefix=charliecloud/ -o "$PREFIX/charliecloud.tar"
        cd "$PREFIX"
        tar xf charliecloud.tar
        cd charliecloud
        ;;
    '')
        ;;
    *)
        false
        ;;
esac

make
bin/ch-run --version

if [[ $INSTALL ]]; then
    sudo make install PREFIX="$PREFIX"
    ch_test="${PREFIX}/bin/ch-test"
else
    ch_test='bin/ch-test'
fi

"$ch_test" mk-perm-dirs --sudo

cd test

if [[ $SUDO_RM_FIRST ]]; then
    sudo rm /etc/sudoers.d/travis
fi
sudo -v || true

"$ch_test" build

ls -lha "$CH_TEST_TARDIR"

if [[ $SUDO_RM_AFTER_BUILD ]]; then
    sudo rm /etc/sudoers.d/travis
fi
if [[ $SUDO_AVOID_AFTER_BUILD ]]; then
    sudo_=''
else
    sudo_='--sudo'
fi
sudo -v || true
echo "\$CH_TEST_SUDO=$CH_TEST_SUDO"

"$ch_test" run "$sudo_"

ls -lh "$CH_TEST_IMGDIR"

"$ch_test" examples
