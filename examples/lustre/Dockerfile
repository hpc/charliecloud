# ch-test-scope: full
# ch-test-arch-exclude: aarch64  # No lustre RPMS for aarch64

FROM centos:8

# Install lustre-client dependencies
RUN dnf install -y --setopt=install_weak_deps=false \
                e2fsprogs-libs \
                wget \
                perl \
 && dnf clean all

ARG LUSTRE_VERSION=2.12.4
ARG LUSTRE_URL=https://downloads.whamcloud.com/public/lustre/lustre-${LUSTRE_VERSION}/el8/client/RPMS/x86_64/

# The lustre-client rpm has a dependency on the kmod-lustre-client rpm, this is
# not required within a container and breaks frequently, using the --nodeps
# flag to work around this.
RUN wget ${LUSTRE_URL}/lustre-client-${LUSTRE_VERSION}-1.el8.x86_64.rpm \
 && rpm -i --nodeps *.rpm \
 && rm -f *.rpm
