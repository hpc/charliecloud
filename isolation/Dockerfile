# Image suitable for isolation testing.

FROM debian:jessie
MAINTAINER Reid Priedhorsky <reidpr@lanl.gov>

# add python 3
RUN apt-get update \
    && apt-get install -y python3 gcc

# security testing stuff
COPY . test
WORKDIR /test
RUN gcc -std=gnu99 -o chroot-escape chroot-escape.c

# cd command is just a shell
WORKDIR /
CMD ["/bin/bash"]
