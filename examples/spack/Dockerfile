# ch-test-scope: full
FROM almalinux:8

# Note: Spack is a bit of an odd duck testing wise. Because it’s a package
# manager, the key tests we want are to install stuff (this includes the Spack
# test suite), and those don’t make sense at run time. Thus, most of what we
# care about is here in the Dockerfile, and test.bats just has a few
# trivialities.
#
# bzip, file, patch, unzip, and which are packages needed to install
# Charliecloud with Spack. These are in Spack’s Docker example [2] but are not
# documented as prerequisites [1]. texinfo is an undocumented dependency of
# Spack’s m4, and that package is in PowerTools, which we enable using sed(1)
# to avoid installing the config-manager DNF plugin.
#
# autoconf, git, openssl, pkg-config, python3, fuse3-libs, fuse3-devel, are
# packages that are typically installed on systems. Thus we install them outside
# of Spack and rely them as externals to speed up the build process.
#
# [1]: https://spack.readthedocs.io/en/latest/getting_started.html
# [2]: https://spack.readthedocs.io/en/latest/workflows.html#using-spack-to-create-docker-images
RUN sed -Ei 's/enabled=0/enabled=1/' \
        /etc/yum.repos.d/almalinux-powertools.repo
RUN dnf install -y --setopt=install_weak_deps=false \
                autoconf \
                automake \
                bzip2 \
                gcc \
                gcc-c++ \
                git \
                gnupg2-smime \
                file \
                fuse3-devel \
                fuse3-libs \
                make \
                patch \
                pkg-config \
                python38 \
                texinfo \
                unzip \
                which \
 && dnf clean all

# Certain Spack packages (e.g., tar) puke if they detect themselves being
# configured as UID 0. This is the override. See issue #540 and [2].
ARG FORCE_UNSAFE_CONFIGURE=1

# Install Spack. This follows the documented procedure to run it out of the
# source directory. There apparently is no “make install” type operation to
# place it at a standard path (“spack clone” simply clones another working
# directory to a new path).
#
# Depending on what’s commented below, we get either Spack’s “develop” branch
# or the latest released version. Using develop catches problems earlier, but
# that branch has a LOT more churn and some of the problems might not occur in
# a released version. I expect the right choice will change over time.
ARG SPACK_REPO=https://github.com/spack/spack
#RUN git clone --depth 1 $SPACK_REPO  # tip of develop; faster clone
RUN git clone $SPACK_REPO && cd spack && git checkout releases/latest  # slow
RUN cd spack && git status && git rev-parse --short HEAD

# Copy our Spack package file; by relying on external packages already installed
# by the container we expedite the spack install process. We do this using
# Spacks config hierarchy, e.g., /etc/spack; however, this file could also be
# placed in the user $HOME/.spack directory.
COPY packages.yaml /etc/spack/

# Apply a patch that resolves issues with Charliecloud 0.35 finding the
# Squashfuse ll.h header. Remove after https://github.com/spack/spack/pull/43374
# is merged and included in the latest spack release.
COPY libfuse.patch /
RUN patch -p 0 < libfuse.patch

# Test some basic commands and install Charliecloud.
# Kludge: here we specify an older python sphinx rtd_theme version because
# newer default version, 0.5.0, introduces a dependency on node-js which doesn’t
# appear to build on gcc 4.8 or gcc 8.3
# (see: https://github.com/spack/spack/issues/19310).
RUN source /spack/share/spack/setup-env.sh \
    && spack --version \
    && spack env create ch \
    && spack env activate ch \
    && spack compiler find \
    && spack compiler list --scope=system \
    && spack compiler list --scope=user \
    && spack compilers \
    && spack add charliecloud +docs +squashfuse ^py-sphinx-rtd-theme@0.4.3 \
    && spack concretize --fresh --force \
    && spack env depfile -o Makefile \
    && make -j $(nproc) SPACK_COLOR=always \
    && spack load charliecloud \
    && ch-run --version \
    && ldd $(which ch-run)

# Clean up.
RUN /spack/bin/spack clean --all
