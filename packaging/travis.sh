#!/bin/bash

set -e

VERSION=$(cat VERSION)
git archive HEAD --format=tar.gz --prefix=charliecloud-${VERSION}/ -o charliecloud-${VERSION}.tar.gz

cd packaging
if [[ $DEBUILD ]]; then
	./debian.sh
fi
if [[ $RPMBUILD ]]; then
	./redhat.sh
fi
