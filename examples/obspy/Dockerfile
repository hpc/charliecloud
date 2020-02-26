# ch-test-scope: skip (issue #64)
FROM debian:stretch

RUN    apt-get update \
    && apt-get install -y \
       bzip2 \
       wget \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda into /usr. Some of the instructions [1] warn against
# putting conda in $PATH; others don't. We are going to play fast and loose.
#
# [1]: http://conda.pydata.org/docs/help/silent.html
WORKDIR /usr/src
ENV MC_VERSION 4.2.12
ENV MC_FILE Miniconda3-$MC_VERSION-Linux-x86_64.sh
RUN wget -nv https://repo.continuum.io/miniconda/$MC_FILE
RUN bash $MC_FILE -bf -p /usr
RUN rm -Rf $MC_FILE
# Disable automatic conda upgrades for predictable versioning.
RUN conda config --set auto_update_conda False

# Install obspy. (Matplotlib 2.0 -- the default as of 2016-01-24 and what
# obspy depends on -- with ObsPy 1.0.2 causes lots of test failures.)
RUN conda config --add channels conda-forge
RUN conda install --yes obspy=1.0.2 \
                        matplotlib=1.5.3 \
                        basemap-data-hires=1.0.8.dev0
