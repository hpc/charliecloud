# FIXME: was full; doesn't work after autotools update
# ch-test-scope: skip
FROM debian9

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
# Note: Spack claims that Python 3 works, but using python3 here fails later
# with "/usr/bin/env: 'python': No such file or directory".
RUN apt-get install -y \
    python \
    gcc \
    make \
    git \
    curl

# Packages needed to install Charliecloud with Spack. These are in Spack's
# Docker example [2] but are not documented as prerequisites [1].
RUN apt-get install -y \
    g++ \
    unzip

# Certain Spack packages (e.g., tar) puke if they detect themselves being
# configured as UID 0. This is the override. See issue #540 and [2].
ARG FORCE_UNSAFE_CONFIGURE=1

# Install Spack. This follows the documented procedure to run it out of the
# source directory. There apparently is no "make install" type operation to
# place it at a standard path ("spack clone" simply clones another working
# directory to a new path).
#
# Spack does have releases, but they seem pretty stale. As of 2019-09-12, the
# most recent version is 0.12.1 dated 8 months ago, 2019-01-13; there have
# been hundreds if not thousands of commits on the default branch "develop"
# since then. We follow develop for this reason and also to catch problems
# installing Charliecloud with latest Spack.
ENV SPACK_REPO https://github.com/spack/spack
#ENV SPACK_VERSION 0.12.1
#RUN git clone --branch v$SPACK_VERSION --depth 1 $SPACK_REPO
RUN git clone --depth 1 $SPACK_REPO
RUN cd spack && git status && git rev-parse --short HEAD

# Set up environment to use Spack. (We can't use setup-env.sh because the
# Dockerfile shell is sh, not Bash.)
ENV PATH /spack/bin:$PATH
RUN spack compiler find --scope system

# Test: Some basic commands.
RUN which spack
RUN spack --version
RUN spack compiler list
RUN spack compiler list --scope=system
RUN spack compiler list --scope=user
RUN spack compilers
RUN spack spec netcdf

# Test: Install Charliecloud.
RUN spack spec charliecloud+builder
RUN spack install charliecloud+builder

# Test: Run Spack test suite. Distro package dependencies discovered by trial
# and error.
#
# FIXME: Commented out because the suite fails. Last time I tried, 6 tests
# failed and 1 "xfailed".
#RUN apt-get install -y \
#    python-pkg-resources
#RUN spack test

# Clean up.
RUN spack clean --all
