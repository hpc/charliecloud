# ch-test-scope: full
FROM debian:stretch

RUN apt-get update \
    && apt-get install -y \
    curl \
    g++ \
    git \
    make \
    patch \
    procps \
    python \
    python-pkg-resources \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Spack
WORKDIR /
ENV SPACK_URL https://github.com/spack/spack.git
ENV SPACK_ROOT /spack
ENV PATH $SPACK_ROOT/bin:$PATH
RUN git clone $SPACK_URL
