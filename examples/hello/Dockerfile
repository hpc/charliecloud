# ch-test-scope: standard
FROM almalinux:8

RUN dnf install -y --setopt=install_weak_deps=false openssh-clients \
 && dnf clean all

COPY . hello
