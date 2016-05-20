# Image suitable for isolation testing.

FROM debian:jessie
MAINTAINER Reid Priedhorsky <reidpr@lanl.gov>

# Install needed packages.
RUN apt-get update \
    && apt-get install -y gcc less make python3

# Testing support software.
COPY . test
WORKDIR /test
RUN make -j$(getconf _NPROCESSORS_ONLN)

# Default command is just a shell.
WORKDIR /
CMD ["/bin/bash"]
