# ch-test-scope: standard
# Unable to convert to a CentOS base until issues #472 and #498 are resolved
FROM debian:stretch

ARG DEBIAN_FRONTEND=noninteractive
RUN    apt-get update \
    && apt-get install -y openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY . hello

RUN touch /usr/bin/ch-ssh
