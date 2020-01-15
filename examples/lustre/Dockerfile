# ch-test-scope: full
# ch-test-builder-exclude: ch-grow  # deferred
FROM centos7

# install development tools
RUN yum install -y epel-release

# more dependencies
RUN yum -y install libyaml-devel \
                   wget \
                   gcc


RUN wget https://downloads.whamcloud.com/public/lustre/latest-release/el7/client/RPMS/x86_64/lustre-client-2.12.3-1.el7.x86_64.rpm && wget https://downloads.whamcloud.com/public/lustre/latest-release/el7/client/RPMS/x86_64/kmod-lustre-client-2.12.3-1.el7.x86_64.rpm

RUN yum localinstall -y *.rpm

WORKDIR /lustre
