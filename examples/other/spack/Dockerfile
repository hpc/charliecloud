# ch-test-scope: full
FROM debian:stretch

RUN apt-get update \
    && apt-get install -y \
    curl \
    g++ \
    git \
    make \ 
    python

# Install Spack
WORKDIR /
ENV SPACK_URL https://github.com/spack/spack.git
ENV SPACK_ROOT /spack
ENV PATH $SPACK_ROOT/bin:$PATH
RUN git clone $SPACK_URL
RUN spack install libelf

# Compiler Verification
RUN spack install zlib%gcc@6.3.0

# Utilities Configuration
RUN spack install curl
RUN spack load curl
RUN spack bootstrap
