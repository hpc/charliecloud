FROM debian8openmpi

# This example
COPY /examples/mpi/mpihello /hello
WORKDIR /hello
RUN make clean && make
