# ch-test-scope: skip (issue #741)
# ch-test-arch-exclude: aarch64  # No lustre RPMS for aarch64

FROM centos7

# install development tools
RUN yum install -y epel-release

# more dependencies
RUN yum -y install libyaml-devel \
                   wget \
                   gcc

ENV LUSTRE_VERSION=2.12.3
ENV LUSTRE_URL=https://downloads.whamcloud.com/public/lustre/lustre-${LUSTRE_VERSION}/el7/client/RPMS/x86_64/

RUN    wget ${LUSTRE_URL}/lustre-client-${LUSTRE_VERSION}-1.el7.x86_64.rpm \
    && wget ${LUSTRE_URL}/kmod-lustre-client-${LUSTRE_VERSION}-1.el7.x86_64.rpm

RUN yum localinstall -y *.rpm
