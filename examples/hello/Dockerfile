# ch-test-scope: standard
FROM centos:centos8

RUN    dnf update -y \
    && dnf install -y openssh-clients \
    && dnf clean all

COPY . hello

RUN touch /usr/bin/ch-ssh
