FROM debian:jessie

# Install needed OS packages.
RUN    apt-get update \
    && apt-get install -y less g++ gcc make openssh-client wget

# Compile OpenMPI. We can't use the Debian package because
# --disable-pty-support is needed to avoid "pipe function call failed when
# setting up I/O forwarding subsystem".
ENV MPI_URL https://www.open-mpi.org/software/ompi/v1.10/downloads
ENV MPI_VERSION 1.10.2
RUN wget -nv ${MPI_URL}/openmpi-${MPI_VERSION}.tar.gz
RUN tar xf openmpi-${MPI_VERSION}.tar.gz
RUN    cd openmpi-${MPI_VERSION} \
    && ./configure --prefix=/usr \
                   --sysconfdir=/etc \
                   --disable-pty-support \
                   --disable-mpi-cxx \
                   --disable-mpi-fortran \
    && make -j$(getconf _NPROCESSORS_ONLN) install

# Configure OpenMPI. We force TCP/IP communication to simulate a cluster.
RUN    echo localhost >> /etc/openmpi-default-hostfile \
    && echo 'plm_rsh_agent = ch-ssh' >> /etc/openmpi-mca-params.conf \
    && echo 'orte_fork_agent = ch-ssh' >> /etc/openmpi-mca-params.conf \
    && echo 'btl = tcp,self' >> /etc/openmpi-mca-params.conf

# ch-ssh is needed for MPI to communicate
COPY bin/ch-ssh /usr/bin

# This example.
COPY examples/mpihello /hello
WORKDIR /hello
RUN make clean && make

# Default command is just a shell.
WORKDIR /
CMD ["/bin/bash"]
