# ch-test-scope: full
FROM debian9

# Note: Spack is a bit of an odd duck testing wise. Because it's a package
# manager, the key tests we want are to install stuff (this includes the Spack
# test suite), and those don't make sense at run time. Thus, most of what we
# care about is here in the Dockerfile, and test.bats just has a few
# trivialities.

# Spack needs curl, git, make, and unzip to install.
# The other packages are needed for Spack unit tests.
RUN apt-get install -y \
    curl \
    g++ \
    git \
    make \
    patch \
    procps \
    python \
    python-pkg-resources \
    unzip

# Install Spack. This follows the documented procedure to run it out of the
# source directory. There apparently is no "make install" type operation to
# place it at a standard path ("spack clone" simply clones another working
# directory to a new path).
ENV SPACK_REPO https://github.com/spack/spack
ENV SPACK_VERSION 0.11.2
RUN git clone --depth 1 $SPACK_REPO
#RUN git clone --branch v$SPACK_VERSION --depth 1 $SPACK_REPO

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

# Test: Install a small package.
RUN spack spec charliecloud
RUN spack install charliecloud

# Test: Run Spack test suite.
# FIXME: Commented out because the suite fails. It's inconsistent; the number
# of failures seems to vary between about 1 and 3 inclusive.
#RUN spack test

# Clean up.
RUN spack clean --all
