# Image suitable for isolation testing.

FROM debian:jessie
MAINTAINER Reid Priedhorsky <reidpr@lanl.gov>

# Install needed packages.
RUN apt-get update \
    && apt-get install -y gcc make python3

# Security testing stuff.
COPY . test
WORKDIR /test
RUN make clean && make

# Default command is just a shell.
WORKDIR /
CMD ["/bin/bash"]
