#!/bin/bash

set -e

sudo apt-get install rpm

VERSION=$(cat ../VERSION)

mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cp ../charliecloud-${VERSION}.tar.gz ~/rpmbuild/SOURCES
cp redhat/charliecloud.spec ~/rpmbuild/SPECS
sed -i "s#Version: @VERSION@#Version: ${VERSION}#g" ~/rpmbuild/SPECS/charliecloud.spec

# Release handled automatically on RedHat systems, but we build on Ubuntu 14.04 here.
sed -i "s#Release: %{?dist}#Release: 1#g" ~/rpmbuild/SPECS/charliecloud.spec

# Remove build requirements, can not be satisfied on Ubuntu / Debian.
sed -i 's#BuildRequires:.*##g' ~/rpmbuild/SPECS/charliecloud.spec

echo "Prepared rpmbuild directory tree:"
find ~/rpmbuild
echo "Now starting build!"

cd ~/rpmbuild/SPECS

rpmbuild -ba charliecloud.spec

echo "Done, tree now:"
find ~/rpmbuild

# RPMLINT not available for 14.04 :-(
#echo "Running rpmlint:"
#cd ~/rpmbuild/RPMS
#rpmlint *
