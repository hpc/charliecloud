# ch-test-scope: full
# ch-test-arch-exclude: aarch64  # No lustre RPMS for aarch64

FROM centos7

# install development tools and dependencies
RUN    yum install -y epel-release \
    && yum -y install libyaml-devel \
                      wget \
                      gcc \
    && yum clean all

ARG LUSTRE_VERSION=2.12.3
ARG LUSTRE_URL=https://downloads.whamcloud.com/public/lustre/lustre-${LUSTRE_VERSION}/el7/client/RPMS/x86_64/

RUN    wget ${LUSTRE_URL}/lustre-client-${LUSTRE_VERSION}-1.el7.x86_64.rpm \
    && wget ${LUSTRE_URL}/kmod-lustre-client-${LUSTRE_VERSION}-1.el7.x86_64.rpm \
    && yum localinstall -y *.rpm \
    && rm -f *.rpm
