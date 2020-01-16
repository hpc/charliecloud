# ch-test-scope: full
FROM mpich

RUN apt-get install -y git

# Compile the Intel MPI benchmark
WORKDIR /usr/local/src
ENV IMB_VERSION 2018.1
RUN git clone --branch v$IMB_VERSION --depth 1 \
              https://github.com/intel/mpi-benchmarks
RUN    cd mpi-benchmarks/src \
    && make CC=mpicc -j$(getconf _NPROCESSORS_ONLN) -f make_ict
