# ch-test-scope: standard
FROM debian:stretch

RUN    apt-get update \
    && apt-get install -y openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY examples/serial/hello hello

RUN touch /usr/bin/ch-ssh
