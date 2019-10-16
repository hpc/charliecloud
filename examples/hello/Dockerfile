# ch-test-scope: standard
# ch-test-builder-exclude: ch-grow  #see issues #472 and #498
FROM centos:centos8

RUN    dnf update -y \
    && dnf install -y openssh-clients \
    && dnf clean all

COPY . hello

RUN touch /usr/bin/ch-ssh
