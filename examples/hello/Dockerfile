FROM debian:jessie
RUN    apt-get update \
    && apt-get install -y openssh-client \
    && rm -rf /var/lib/apt/lists/*
RUN touch /usr/bin/ch-ssh
