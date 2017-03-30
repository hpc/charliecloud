FROM debian:jessie

# OS packages needed to build OpenMPI.
RUN    apt-get update \
    && apt-get install -y g++ gcc make wget \
    && rm -rf /var/lib/apt/lists/*

# Compile OpenMPI. We can't use the Debian package because
# --disable-pty-support is needed to avoid "pipe function call failed when
# setting up I/O forwarding subsystem".
ENV MPI_URL https://www.open-mpi.org/software/ompi/v1.10/downloads
ENV MPI_VERSION 1.10.5
RUN wget -nv ${MPI_URL}/openmpi-${MPI_VERSION}.tar.gz
RUN tar xf openmpi-${MPI_VERSION}.tar.gz
RUN    cd openmpi-${MPI_VERSION} \
    && CFLAGS=-O3 CXXFLAGS=-O3 \
       ./configure --prefix=/usr --sysconfdir=/mnt/0 \
                   --disable-pty-support \
                   --disable-mpi-cxx --disable-mpi-fortran \
    && make -j$(getconf _NPROCESSORS_ONLN) install
RUN rm -Rf openmpi-${MPI_VERSION}*

# This example
COPY examples/mpihello /hello
WORKDIR /hello
RUN make clean && make
