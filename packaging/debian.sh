#!/bin/bash

set -e

sudo apt-get install devscripts build-essential lintian debhelper

VERSION=$(cat ../VERSION)

mkdir ../debuild
cd ../debuild
tar xf ../charliecloud-${VERSION}.tar.gz
cd charliecloud-${VERSION}
cp -r packaging/debian .
sed -i "s#@VERSION@#${VERSION}#g" debian/changelog

# Symlink sphinx-build into sanitized path, so debuild can use it.
sudo ln -s /usr/local/bin/sphinx-build /usr/bin/sphinx-build

echo "Prepared debuild directory in $(pwd):"
ls -la
echo "Now starting build!"

# We have to use -d here, since dependencies can not be satisfied on trusty.
# We install sphinx and the rtd-theme via pip before.
# We have to use -fno-builtin -fPIC to hack around the broken 14.04 travis image.
DEB_CFLAGS_SET="-fno-builtin -fPIC" debuild -d -i -us -uc
