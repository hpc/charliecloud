FROM debian:jessie

RUN    apt-get update \
    && apt-get install -y openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY examples/hello hello

RUN touch /usr/bin/ch-ssh
