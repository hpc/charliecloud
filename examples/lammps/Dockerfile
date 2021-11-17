# ch-test-scope: full
FROM openmpi
WORKDIR /usr/local/src

# Packages for building.
RUN dnf install -y --setopt=install_weak_deps=false \
                cmake \
                patch \
                python3-devel \
                python3-pip \
                python3-setuptools \
 && dnf clean all

# Building mpi4py from source to ensure it is built against our MPI build
# Building numpy from source to work around issues seen on Aarch64 systems
RUN pip3 install --no-binary :all: cython==0.29.24 mpi4py==3.1.1 numpy==1.19.5
#RUN ln -s /usr/bin/python3 /usr/bin/python
# Build LAMMPS.
ARG LAMMPS_VERSION=29Sep2021
RUN wget -nv https://github.com/lammps/lammps/archive/patch_${LAMMPS_VERSION}.tar.gz \
 && tar xf patch_$LAMMPS_VERSION.tar.gz \
 && mkdir lammps-${LAMMPS_VERSION}.build \
 && cd lammps-${LAMMPS_VERSION}.build \
 && cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_MPI=yes \
          -DBUILD_LIB=on \
          -DBUILD_SHARED_LIBS=on \
          -DPKG_DIPOLE=yes \
          -DPKG_KSPACE=yes \
          -DPKG_POEMS=yes \
          -DPKG_PYTHON=yes \
          -DPKG_USER-REAXC=yes \
          -DPKG_USER-MEAMC=yes \
          -DLAMMPS_MACHINE=mpi \
    ../lammps-patch_${LAMMPS_VERSION}/cmake \
 && make -j $(getconf _NPROCESSORS_ONLN) install \
 && ln -s /usr/local/src/lammps-patch_${LAMMPS_VERSION}/ /lammps \
 && rm -f ../patch_$LAMMPS_VERSION.tar.gz
RUN ldconfig

# Patch in.melt to increase problem dimensions.
COPY melt.patch /lammps/examples/melt
RUN patch -p1 -d / < /lammps/examples/melt/melt.patch
# Patch simple.py to uncomment mpi4py calls and disable file output.
# Patch in.simple to increase problem dimensions.
COPY simple.patch /lammps/python/examples
RUN patch -p1 -d / < /lammps/python/examples/simple.patch
