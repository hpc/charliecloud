# ch-test-scope: full
FROM debian9

# A key goal of this Dockerfile is to demonstrate best practices for building
# OpenMPI for use inside a container.
#
# This OpenMPI aspires to work close to optimally on clusters with any of the
# following interconnects:
#
#    - Ethernet (TCP/IP)
#    - InfiniBand (IB)
#    - Omni-Path (OPA)
#    - RDMA over Converged Ethernet (RoCE) interconnects
#
# with no environment variables, command line arguments, or additional
# configuration files. Thus, we try to implement decisions at build time.
#
# This is a work in progress, and we're very interested in feedback.
#
# OpenMPI has numerous ways to communicate messages [1]. The ones relevant to
# this build and the interconnects they support are:
#
#   Module        Eth   IB    OPA   RoCE    note  decision
#   ------------  ----  ----  ----  ----    ----  --------
#
#   ob1 : tcp      Y*    X     X     X      a     include
#   ob1 : openib   N     Y     Y     Y      b,c   exclude
#   cm  : psm2     N     N     Y*    N            include
#       : ucx      Y?    Y*    N     Y?     b,d   include
#
#   Y : supported
#   Y*: best choice for that interconnect
#   X : supported but sub-optimal
#
#   a : No RDMA, so performance will suffer.
#   b : Uses libibverbs.
#   c : Will be removed in OpenMPI 4.
#   d : Uses Mellanox libraries if available in preference to libibverbs.
#
# You can check what's available with:
#
#   $ ch-run /var/tmp/openmpi -- ompi_info | egrep '(btl|mtl|pml)'
#
# The other build decisions are:
#
#   1. PMI/PMIx: Include these so that we can use srun or any other PMI[x]
#      provider, with no matching OpenMPI needed on the host.
#
#   2. --disable-pty-support to avoid "pipe function call failed when
#      setting up I/O forwarding subsystem".
#
#   3. --enable-mca-no-build=plm-slurm to support launching processes using
#      the host's srun (i.e., the container OpenMPI needs to talk to the host
#      Slurm's PMI) but prevent OpenMPI from invoking srun itself from within
#      the container, where srun is not installed (the error messages from
#      this are inscrutable).
#
# [1]: https://github.com/open-mpi/ompi/blob/master/README

# OS packages needed to build this stuff.
RUN apt-get install -y --no-install-suggests \
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

WORKDIR /usr/local/src

# Use the Buster versions of libpsm2 (not present in Stretch) and libibverbs
# (too old in Stretch). Download manually because I'm too lazy to set up
# package pinning.
#
# Note that libpsm2 is x86-64 only:
#   https://packages.debian.org/buster/libpsm2-2
#   https://lists.debian.org/debian-hpc/2017/12/msg00015.html
ENV DEB_URL http://snapshot.debian.org/archive/debian/20181126T030749Z/pool/main
ENV PSM2_VERSION 11.2.68-3
RUN if [ "$(dpkg --print-architecture)" = "amd64" ] ; then \
      wget -nv ${DEB_URL}/libp/libpsm2/libpsm2-2_${PSM2_VERSION}_amd64.deb \
               ${DEB_URL}/libp/libpsm2/libpsm2-dev_${PSM2_VERSION}_amd64.deb ; \
    fi
# As of 5/2/2019, this is not the newest libibverbs. However, it is the
# newest that doesn't crash on our test systems.
ENV IBVERBS_VERSION 20.0-1
RUN for i in ibacm \
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
        wget -nv ${DEB_URL}/r/rdma-core/${i}_${IBVERBS_VERSION}_$(dpkg --print-architecture).deb ; \
    done

# Install the .debs we collected. UCX needs these.
RUN dpkg --install *.deb

# UCX. There is stuff to build Debian packages, but it seems not too polished.
ENV UCX_VERSION 1.3.1
RUN git clone --branch v${UCX_VERSION} --depth 1 \
              https://github.com/openucx/ucx.git
RUN    cd ucx \
    && ./autogen.sh \
    && ./contrib/configure-release --prefix=/usr/local \
    && make -j$(getconf _NPROCESSORS_ONLN) install

# OpenMPI.
#
# Patch OpenMPI to disable UCX plugin on systems with Intel or Cray HSNs. UCX
# has inferior performance than PSM2/uGNI but higher priority.
ENV MPI_URL https://www.open-mpi.org/software/ompi/v3.1/downloads
ENV MPI_VERSION 3.1.4
RUN wget -nv ${MPI_URL}/openmpi-${MPI_VERSION}.tar.gz
RUN tar xf openmpi-${MPI_VERSION}.tar.gz
COPY dont-init-ucx-on-intel-cray.patch ./openmpi-${MPI_VERSION}
RUN cd openmpi-${MPI_VERSION} && git apply dont-init-ucx-on-intel-cray.patch
RUN    cd openmpi-${MPI_VERSION} \
    && CFLAGS=-O3 \
       CXXFLAGS=-O3 \
       ./configure --prefix=/usr/local \
                   --sysconfdir=/mnt/0 \
		   --with-slurm \
                   --with-pmi \
                   --with-pmix \
                   --with-ucx \
                   --disable-pty-support \
                   --enable-mca-no-build=btl-openib,plm-slurm \
    && make -j$(getconf _NPROCESSORS_ONLN) install
RUN ldconfig
RUN rm -Rf openmpi-${MPI_VERSION}*

# OpenMPI expects this program to exist, even if it's not used. Default is
# "ssh : rsh", but that's not installed.
RUN echo 'plm_rsh_agent = false' >> /mnt/0/openmpi-mca-params.conf
