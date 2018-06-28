# ch-test-scope: full
FROM mpich

COPY /examples/mpi/mpihello /hello
WORKDIR /hello
RUN make clean && make
