# ch-test-scope: standard
FROM centos:7

# This image has two purposes: (1) demonstrate we can build a CentOS 7 image
# and (2) provide a build environment for Charliecloud RPMs.

RUN yum -y install epel-release
RUN yum -y install \
           bats \
           gcc \
           make \
           python36 \
           rpm-build \
           rpmlint \
           wget
RUN yum clean all
