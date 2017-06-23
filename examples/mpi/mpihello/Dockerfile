FROM debian:jessie

# OS packages needed to build OpenMPI.
RUN    apt-get update && apt-get install -y g++ gcc make wget \
    && rm -rf /var/lib/apt/lists/*

# Compile OpenMPI.
ENV VERSION 1.10.5
RUN wget -nv https://www.open-mpi.org/software/ompi/v1.10/downloads/openmpi-${VERSION}.tar.gz
RUN tar xf openmpi-${VERSION}.tar.gz
RUN    cd openmpi-${VERSION} \
    && CFLAGS=-O3 CXXFLAGS=-O3 \
       ./configure --prefix=/usr --sysconfdir=/mnt/0 \
                   --disable-pty-support --disable-mpi-cxx --disable-mpi-fortran \
    && make -j$(getconf _NPROCESSORS_ONLN) install
RUN rm -Rf openmpi-${VERSION}*

# This example
COPY /examples/mpi/mpihello /hello
WORKDIR /hello
RUN make clean && make
