FROM debian:jessie

# Install needed OS packages.
RUN    apt-get update \
    && apt-get install -y less g++ gcc make wget

# Source goes here
WORKDIR /usr/local/src

# Compile OpenMPI. We can't use the Debian package because
# --disable-pty-support is needed to avoid "pipe function call failed when
# setting up I/O forwarding subsystem".
ENV MPI_URL https://www.open-mpi.org/software/ompi/v1.6/downloads
ENV MPI_VERSION 1.6.5
RUN wget -nv ${MPI_URL}/openmpi-${MPI_VERSION}.tar.gz
RUN tar xf openmpi-${MPI_VERSION}.tar.gz
RUN    cd openmpi-${MPI_VERSION} \
    && ./configure --prefix=/usr \
                   --sysconfdir=/etc \
                   --disable-pty-support \
                   --disable-mpi-cxx \
                   --disable-mpi-fortran \
    && make -j$(getconf _NPROCESSORS_ONLN) install

# Compile the Intel MPI benchmark. Note that this URL comes from a button
# labeled "Accept", so you may want to go click it before building the image.
ENV IMB_VERSION 4.1
RUN wget -nv https://software.intel.com/sites/default/files/managed/a3/b2/IMB_${IMB_VERSION}.tgz
RUN tar xf IMB_${IMB_VERSION}.tgz
# The benchmark won't compile in parallel.
RUN    cd imb/src \
    && make CC=mpicc -j1 -f make_ict IMB-MPI1
