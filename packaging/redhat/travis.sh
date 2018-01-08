#!/bin/bash

# Build a .rpm from the current source code diretory. $PWD must be the root of
# the Charliecloud source code.
#
# Because this is designed to work on a Ubuntu box, which is Debian-based
# rather than Red Hat, some things are a little odd.

set -e
set -x

sudo apt-get install rpm

RPMBUILD=~/rpmbuild
mkdir -p $RPMBUILD/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

make VERSION.full
VERSION=$(cat VERSION.full)

tar czf $RPMBUILD/SOURCES/charliecloud-${VERSION}.tar.gz \
    --xform "s#^\.#charliecloud-${VERSION}#" \
    --exclude=.git \
    .

cp packaging/redhat/charliecloud.spec $RPMBUILD/SPECS
sed -i "s#Version: @VERSION@#Version: ${VERSION}#g" $RPMBUILD/SPECS/charliecloud.spec

# This is handled automatically on Red Hat systems.
sed -i "s#Release: %{?dist}#Release: 1#g" ~/rpmbuild/SPECS/charliecloud.spec

# Build requirements cannot be satisfied on Debian derivatives.
sed -i 's#BuildRequires:.*##g' ~/rpmbuild/SPECS/charliecloud.spec

#echo "Prepared rpmbuild directory tree:"
#find $RPMBUILD
#cho "Now starting build!"

cd $RPMBUILD/SPECS

rpmbuild -ba charliecloud.spec

#echo "Done, tree now:"
#find $RPMBUILD

# RPMLINT not available for 14.04 :-(
#echo "Running rpmlint:"
#cd $RPMBUILD/RPMS
#rpmlint *
