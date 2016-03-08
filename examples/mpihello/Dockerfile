FROM debian:jessie
MAINTAINER Reid Priedhorsky <reidpr@lanl.gov>

# Install needed OS packages.
RUN    apt-get update \
    && apt-get install -y less g++ gcc make openssh-client wget

# Compile OpenMPI. We can't use the OS package because --disable-pty-support
# is needed to avoid "pipe function call failed when setting up I/O forwarding
# subsystem".
RUN wget -q https://www.open-mpi.org/software/ompi/v1.6/downloads/openmpi-1.6.5.tar.gz
RUN tar xf openmpi-1.6.5.tar.gz
RUN    cd openmpi-1.6.5 \
    && ./configure --prefix=/usr \
                   --disable-pty-support \
                   --disable-mpi-cxx \
                   --disable-mpi-f77 \
                   --disable-mpi-f90 \
    && make -j$(getconf _NPROCESSORS_ONLN) install

# This example.
COPY . /hello
WORKDIR /hello
RUN make clean && make

# Default command is just a shell.
WORKDIR /
CMD ["/bin/bash"]
