FROM openmpi

# Compile the Intel MPI benchmark. Note that this URL comes from a button
# labeled "Accept", so you may want to go click it before building the image.
WORKDIR /usr/src
ENV IMB_VERSION 2017
RUN wget -nv https://software.intel.com/sites/default/files/managed/a3/53/IMB_${IMB_VERSION}.tgz
RUN tar xf IMB_${IMB_VERSION}.tgz --strip 1
# The benchmark won't compile in parallel.
RUN    cd imb/src \
    && make CC=mpicc -j1 -f make_ict
