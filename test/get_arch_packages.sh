#!/bin/bash

# This is a helper script to juggle aarch64 vs x86-64 packages from one
# Dockerfile

# OS packages needed to build this stuff.
apt-get install -y --no-install-suggests \
    autoconf \
    file \
    flex \
    g++ \
    gcc \
    gfortran \
    git \
    hwloc-nox \
    less \
    libdb5.3-dev \
    libhwloc-dev \
    libnl-3-200 \
    libnl-route-3-200 \
    libnl-route-3-dev \
    libnuma1 \
    libpmi2-0-dev \
    make \
    wget \
    udev

# Use the Buster versions of libpsm2 (not present in Stretch) and libibverbs
# (too old in Stretch). Download manually because I'm too lazy to set up
# package pinning.
#
# Note that libpsm2 is x86-64 only:
#   https://packages.debian.org/buster/libpsm2-2
#   https://lists.debian.org/debian-hpc/2017/12/msg00015.html

ARCH="$(dpkg --print-architecture)"

DEB_URL=http://snapshot.debian.org/archive/debian/20181231T220010Z/pool/main
PSM2_VERSION=11.2.68-4
if [[ $ARCH = "amd64" ]]; then
    wget -nv "${DEB_URL}/libp/libpsm2/libpsm2-2_${PSM2_VERSION}_amd64.deb"
    wget -nv "${DEB_URL}/libp/libpsm2/libpsm2-dev_${PSM2_VERSION}_amd64.deb"
fi

# As of 4/22/2019, this is not the newest libibverbs. However, it is the
# newest that doesn't crash on our test systems.
IBVERBS_VERSION=21.0-1
for i in ibacm \
             ibverbs-providers \
             ibverbs-utils \
             libibumad-dev \
             libibumad3 \
             libibverbs-dev \
             libibverbs1 \
             librdmacm-dev \
             librdmacm1 \
             rdma-core \
             rdmacm-utils ; \
    do \
        wget -nv "${DEB_URL}/r/rdma-core/${i}_${IBVERBS_VERSION}_${ARCH}.deb" ; \
    done
dpkg --install ./*.deb
