# ch-test-scope: full
FROM openmpi
WORKDIR /

# Packages for building.
RUN apt-get install -qy --no-install-recommends \
    git \
    patch \
    python-dev

# Build LAMMPS.
ENV LAMMPS_VERSION 17Nov16
ENV LAMMPS_DIR lammps-$LAMMPS_VERSION
ENV LAMMPS_TAR $LAMMPS_DIR.tar.gz
RUN wget -nv http://lammps.sandia.gov/tars/$LAMMPS_TAR
RUN tar xf $LAMMPS_TAR
RUN    cd $LAMMPS_DIR/src \
    && python Make.py -j $(getconf _NPROCESSORS_ONLN) -p none \
              std no-lib reax meam poems python reaxc orig -a lib-all mpi
RUN    mv $LAMMPS_DIR/src/lmp_mpi /usr/bin \
    && ln -s ./$LAMMPS_DIR /lammps
RUN    cd $LAMMPS_DIR/python \
    && python2.7 install.py

# Make another test input file.
# Patch instead of including in.large.melt in full because LAMMPS is GPL.
COPY melt.patch /lammps/examples/melt
RUN patch -p1 -o /lammps/examples/melt/in.large.melt \
               < /lammps/examples/melt/melt.patch
