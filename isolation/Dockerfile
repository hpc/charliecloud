# Image suitable for isolation testing.

FROM debian:jessie
MAINTAINER Reid Priedhorsky <reidpr@lanl.gov>

# Install needed packages.
RUN apt-get update \
    && apt-get install -y gcc less make python3

# Testing support software.
COPY . test
WORKDIR /test
RUN make -j4

# Leave a gaping back door in /etc/shadow (no password for root).
#RUN sed -iE 's/root:\*:/root::/' /etc/shadow

# Default command is just a shell.
WORKDIR /
CMD ["/bin/bash"]
