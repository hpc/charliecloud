FROM centos:7

RUN yum install -y epel-release \
                   dnf \
                   gcc \
                   rpm-build \
                   rpm-devel \
                   rpmlint \
                   rsync \
                   wget \
                   make \
                   python \
                   bash \
                   coreutils \
                   diffutils \
                   patch \
                   rpmdevtools
RUN yum clean all
RUN rpmdev-setuptree
COPY charliecloud.spec /root/rpmbuild/SPECS
COPY charliecloud-*.tar.gz /root/rpmbuild/SOURCES

# @VERSION@, @RELEASE@, and @DATE@ are replaced with contents in travis.sh.
ARG version="@VERSION@"
ARG release="@RELEASE@"
ARG date="@DATE@"

RUN sed -i "s/VERSION/${version}/g" /root/rpmbuild/SPECS/charliecloud.spec; \
    sed -i "s/RELEASE/${release}/g" /root/rpmbuild/SPECS/charliecloud.spec; \
    sed -i "s/DATE/${date}/g" /root/rpmbuild/SPECS/charliecloud.spec; \
    rpmbuild -ba /root/rpmbuild/SPECS/charliecloud.spec; \
    dnf install -y /root/rpmbuild/RPMS/x86_64/charliecloud-${version}-${release}.el7.x86_64.rpm; \
    dnf install -y /root/rpmbuild/RPMS/x86_64/charliecloud-doc-${version}-${release}.el7.x86_64.rpm

# TODO: Add rpmlint and config files that silence false positive errors
# RUN rpmlint charliecloud
# RUN rpmlint charliecloud-doc

FROM centos:7

COPY --from=0 /root/rpmbuild/RPMS/x86_64/charliecloud-* /
COPY --from=0 /root/rpmbuild/SPECS/charliecloud.spec /
