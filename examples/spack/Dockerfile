# ch-test-scope: full
FROM centos:8

# Note: Spack is a bit of an odd duck testing wise. Because it's a package
# manager, the key tests we want are to install stuff (this includes the Spack
# test suite), and those don't make sense at run time. Thus, most of what we
# care about is here in the Dockerfile, and test.bats just has a few
# trivialities.
#
# Spack does document use in Docker [2]. We do things somewhat differently,
# but worth reviewing those docs.
#
# [1]: https://spack.readthedocs.io/en/latest/getting_started.html
# [2]: https://spack.readthedocs.io/en/latest/workflows.html#using-spack-to-create-docker-images

# Packages needed to install Spack [1].
#
# bzip, file, patch, unzip, and which are packages needed to install
# Charliecloud with Spack. These are in Spack's Docker example [2] but are not
# documented as prerequisites [1].
RUN dnf install -y --setopt=install_weak_deps=false \
                gcc \
                gcc-c++ \
                git \
                gnupg2-smime \
                python3 \
                make \
                bzip2 \
                file \
                patch \
                unzip \
                which \
 && dnf clean all

# Certain Spack packages (e.g., tar) puke if they detect themselves being
# configured as UID 0. This is the override. See issue #540 and [2].
ARG FORCE_UNSAFE_CONFIGURE=1

# Install Spack. This follows the documented procedure to run it out of the
# source directory. There apparently is no "make install" type operation to
# place it at a standard path ("spack clone" simply clones another working
# directory to a new path).
#
# We follow the develop branch to catch problems installing Charliecloud with
# the latest Spack.
ARG SPACK_REPO=https://github.com/spack/spack
RUN git clone --depth 1 $SPACK_REPO
RUN cd spack && git status && git rev-parse --short HEAD
ARG SPACK_ROOT=/spack
# Setup internal repo
RUN mkdir $SPACK_ROOT/share/spack/bootstrap/internal
RUN cp $SPACK_ROOT/share/spack/bootstrap/github-actions/clingo.json $SPACK_ROOT/share/spack/bootstrap/internal
COPY bootstrap.yaml $SPACK_ROOT/etc/spack/bootstrap.yaml
# Need this to exist to bind-mount
RUN mkdir /spack/opt

# Disable spack-install and github-actions by making them untrusted
RUN sed -i 's/spack-install: true/spack-install: false/' /spack/etc/spack/defaults/bootstrap.yaml
RUN sed -i 's/github-actions: true/github-actionss: false/' /spack/etc/spack/defaults/bootstrap.yaml

# Set up environment to use Spack. (We can't use setup-env.sh because the
# Dockerfile shell is sh, not Bash.)
ENV PATH /spack/bin:$PATH
RUN spack compiler find --scope system

# Thse RUN tests don't work with the new configuration so I'm commenting them
# out for now. 
# Test: Some basic commands.
#RUN which spack
#RUN spack --version
#RUN spack compiler find
#RUN spack compiler list
#RUN spack compiler list --scope=system
#RUN spack compiler list --scope=user
#RUN spack compilers
#RUN spack spec charliecloud
#
## Test: Install Charliecloud.
## Kludge: here we specify an older python sphinx rtd_theme version because
## newer default version, 0.5.0, introduces a dependency on node-js which doesn't
## appear to build on gcc 4.8 or gcc 8.3
## (see: https://github.com/spack/spack/issues/19310).
#RUN spack spec charliecloud+docs^py-sphinx-rtd-theme@0.4.3
#RUN spack install charliecloud+docs^py-sphinx-rtd-theme@0.4.3
#
## Clean up.
#RUN spack clean --all
