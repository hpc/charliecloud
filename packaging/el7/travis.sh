#!/bin/bash

# This script builds a centos 7 container that generates: 
#   1. charliecloud.spec file, 
#   2. charliecloud-{version}-{release}.el7.x86_64.rpm,
#   3. charliecloud-doc-{version}-{release}.el7.x86_64.rpm; and
# then installs and tests the generated artifacts within the container.

# $PWD is assumed to be the root directory charliecloud source code

set -e
set -x

fatal() {
    printf '%s\n\n' "$1" >&2
    exit 1 
}

version="$(cat VERSION.full)"
make export

# rpmbuild will not allow a spec file to have special characters (e.g., '~')
# in Version. Thus, the contents of VERSION.txt are modified for non-
# release commits, i.e, when VERSION.txt contains anything other than a 
# release version number.
mv "charliecloud-${version}.tar.gz" "charliecloud-${version/~pre*/}.tar.gz"
version="${version/~pre*/}"
mv "charliecloud-${version}.tar.gz" packaging/el7/ \
    || fatal "can't move tarball to packaging/el7/"

cd ./packaging/el7 || fatal "can't cd to packaging/el7"

# FIXME: prefer to rename the top-level directory to 
# charliecloud-${version} instead of unpacking tar, renaming, and then
# packing the folder back into a tarball
tar xf "charliecloud-${version}.tar.gz"
mv "charliecloud-${version}~pre"* "charliecloud-${version}"
tar cvzf "charliecloud-${version}.tar.gz" "charliecloud-${version}" 
rm -rf "charliecloud-${version}"

date="$(date +"%a %b %d %Y")"

# FIXME: Figure out how to determine changelog comments.
echo "release: 1" > RELEASE.txt
release=$(cat RELEASE.txt | sed 's,release: ,,g')

cp Dockerfile "Dockerfile.${version}-${release}"
sed -i "s,@VERSION@,${version},g" "Dockerfile.${version}-${release}"
sed -i "s,@RELEASE@,${release},g" "Dockerfile.${version}-${release}"
sed -i "s,@DATE@,${date},g" "Dockerfile.${version}-${release}"

tag="${version/~pre*/}"
tag="pre_${tag}"
ch-build -t "${tag}_${release}" --file="Dockerfile.${version}-${release}" .
rm "Dockerfile.${version}-${release}"
rm "charliecloud-${version}.tar.gz"
