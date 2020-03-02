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

./autogen.sh

# Remove Autotools to make sure everything works without them.
sudo apt-get remove autoconf autoconf-archive automake

if [[ $MINIMAL_CONFIG ]]; then
    # Everything except --disable-test, which would defeat the point.
    disable='--disable-html --disable-man --disable-ch-grow'
fi

case $TARBALL in
    export)
        # shellcheck disable=SC2086
        ./configure --prefix="$PREFIX" $disable
        make dist
        mv charliecloud-*.tar.gz "$PREFIX"
        cd "$PREFIX"
        tar xf charliecloud-*.tar.gz
        rm charliecloud-*.tar.gz
        cd charliecloud-*
        ;;
    archive)
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

# shellcheck disable=SC2086
./configure --prefix="$PREFIX" $disable
make
bin/ch-run --version

if [[ $MAKE_INSTALL ]]; then
    sudo make install
    ch_test="${PREFIX}/bin/ch-test"
else
    ch_test=$(readlink -f bin/ch-test)  # need absolute path
fi

"$ch_test" mk-perm-dirs --sudo

if [[ $SUDO_RM_FIRST ]]; then
    sudo rm /etc/sudoers.d/travis
fi
if ( sudo -v ); then
    sudo_=--sudo
else
    sudo_=
fi

"$ch_test" build $sudo_
ls -lha "$CH_TEST_TARDIR"

if [[ $SUDO_RM_AFTER_BUILD ]]; then
    sudo rm /etc/sudoers.d/travis
fi
if ( sudo -v ); then
    sudo_=--sudo
else
    sudo_=
fi

"$ch_test" run $sudo_
ls -lha "$CH_TEST_IMGDIR"
"$ch_test" examples $sudo_
