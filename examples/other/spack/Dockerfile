# ch-test-scope: full
FROM debian:stretch

RUN apt-get update \
    && apt-get install -y \
    apt-utils \
    curl \
    g++ \
    gfortran \
    git \
    make \
    mercurial \
    patch \
    procps \
    python \
    python-pkg-resources\
    tar \
    unzip

# Install Spack
WORKDIR /
ENV SPACK_URL https://github.com/spack/spack.git
ENV SPACK_ROOT /spack
ENV PATH $SPACK_ROOT/bin:$PATH
RUN git clone $SPACK_URL
RUN spack install libelf
RUN spack bootstrap
