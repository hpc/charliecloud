# ch-test-scope: full
# ch-test-arch-exclude: aarch64  # no obspy Conda package
# ch-test-arch-exclude: ppc64le  # no obspy Conda package?
FROM almalinux_8ch

RUN dnf install -y --setopt=install_weak_deps=false \
                zlib-devel \
 && dnf clean all

WORKDIR /usr/local/src

# Install Miniconda. Notes/gotchas:
#
#   1. Install into /usr/local. Some of the instructions [e.g., 1] warn
#      against putting conda in $PATH; others don’t. However it seems to work
#      and then we don’t need to muck with the path.
#
#   2. Use latest version so we catch sooner if things explode.
#
#   3. ObsPy 1.4.0, the latest as of 2024-03-27, is incompatible with Python
#      3.12 [2], which is recently the default in Miniconda (see PR #XXXX and
#      issue #XXXX).
#
# [1]: https://docs.anaconda.com/anaconda/user-guide/faq/
# [2]: https://github.com/obspy/obspy/issues/3313#issuecomment-1818165937
ARG MC_VERSION=py311_24.1.2-0
ARG MC_FILE=Miniconda3-$MC_VERSION-Linux-x86_64.sh
RUN wget -nv https://repo.anaconda.com/miniconda/$MC_FILE
# Miniconda will fail if the HOME variable is not set.
RUN HOME=/home bash $MC_FILE -bf -p /usr/local
RUN rm -Rf $MC_FILE
RUN which conda && conda --version
# Disable automatic conda upgrades for predictable versioning.
RUN conda config --set auto_update_conda False

# Install obspy, also latest. This is a container, so don’t bother creating a
# new environment for obspy.
# See: https://github.com/obspy/obspy/wiki/Installation-via-Anaconda
RUN conda config --add channels conda-forge
RUN conda install --yes obspy=1.4.0
RUN conda update obspy

# Hello world program and input from docs.
WORKDIR /
RUN wget -nv http://examples.obspy.org/RJOB_061005_072159.ehz.new
COPY hello.py .
RUN chmod 755 ./hello.py
RUN ldconfig
