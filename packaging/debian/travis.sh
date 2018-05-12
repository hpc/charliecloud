#!/bin/bash

# Build a .deb from the current source code directory. $PWD must be the root
# of the Charliecloud source code.
#
# FIXME: This uses the latest debian/changelog entry to choose the package
# version, which is wrong most of the time. I'd really like to just be able to
# say "debuild" at the source code root, without needing e.g. sed beforehand.
# What is the best practice here? This must not be the only package with this
# problem.

set -e
set -x

# Need these packages to build.
sudo apt-get install devscripts build-essential lintian debhelper

# debuild needs Sphinx in the sanitized path
# We install sphinx and the rtd-theme via pip in travis.yml.
sudo ln -f -s /usr/local/bin/sphinx-build /usr/bin/sphinx-build

# Need -d because dependencies can not be satisfied on trusty.
# Need -fno-builtin -fPIC to hack around the broken 14.04 travis image.
ln -s packaging/debian
DEB_CFLAGS_SET="-fno-builtin -fPIC" debuild -d -i -us -uc
