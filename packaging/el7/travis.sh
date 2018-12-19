#!/bin/bash

# Build a container with rpmbuild and rpmlint; copy in charliecloud version,
# release, and spec file into container image; build container and build 
# charliecloud rpm based on the provided version and release.
#
# $PWD is assumed to be the root directory charliecloud source code

set -e
set -x

err() {
    echo "$1: $LINENO"
    exit 1 
}

version="$(cat VERSION.full)"
make export

# Spec files do not allow special characters e.g., '-', '~'.
mv "charliecloud-${version}.tar.gz" "charliecloud-${version/~pre*/}.tar.gz"
version="${version/~pre*/}"
mv "charliecloud-${version}.tar.gz" packaging/el7/ \
    || err "can't move tarball to packaging/el7/"

cd ./packaging/el7 || err "can't cd to packaging/el7"

# FIXME: prefer to rename the top-level directory to 
# charliecloud-${version} instead of unpacking tar, renaming, and then
# packing the folder back into a tarball
tar xf "charliecloud-${version}.tar.gz"
mv "charliecloud-${version}~pre"* "charliecloud-${version}"
tar cvzf "charliecloud-${version}.tar.gz" "charliecloud-${version}" 
rm -rf "charliecloud-${version}"

date="$(date +"%a %b %d %Y")"

# TODO: get release number from file e.g. RELEASE.txt
release="1"

cp Dockerfile "Dockerfile.${version}-${release}"
sed -i "s,@VERSION@,${version},g" "Dockerfile.${version}-${release}"
sed -i "s,@RELEASE@,${release},g" "Dockerfile.${version}-${release}"
sed -i "s,@DATE@,${date},g" "Dockerfile.${version}-${release}"

tag="${version/~pre*/}"
tag="pre_${tag}"
ch-build -t "${tag}_${release}" --file="Dockerfile.${version}-${release}" .
rm "Dockerfile.${version}-${release}"
rm "charliecloud-${version}.tar.gz"
