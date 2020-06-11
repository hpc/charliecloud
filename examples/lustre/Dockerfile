# ch-test-scope: full
# ch-test-arch-exclude: aarch64  # No lustre RPMS for aarch64

FROM centos8

# Install lustre-client dependencies
RUN dnf install -y --setopt=install_weak_deps=false \
                e2fsprogs-libs \
                kernel-core \
                libyaml-devel \
                linux-firmware \
 && dnf clean all

ARG LUSTRE_VERSION=2.12.4
ARG LUSTRE_URL=https://downloads.whamcloud.com/public/lustre/lustre-${LUSTRE_VERSION}/el8/client/RPMS/x86_64/

RUN wget ${LUSTRE_URL}/lustre-client-${LUSTRE_VERSION}-1.el8.x86_64.rpm \
 && wget ${LUSTRE_URL}/kmod-lustre-client-${LUSTRE_VERSION}-1.el8.x86_64.rpm \
 && rpm --install *.rpm \
 && rm -f *.rpm
