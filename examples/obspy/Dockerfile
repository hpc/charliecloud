# ch-test-scope: quick
FROM debian:buster

RUN    apt-get update \
    && apt-get install -y \
       bzip2 \
       wget \
    && rm -rf /var/lib/apt/lists/*


# Install Miniconda into /usr/local. Some of the instructions [1] warn against
# putting conda in $PATH; others don't. We are going to play fast and loose.
#
# [1]: http://conda.pydata.org/docs/help/silent.html
WORKDIR /usr/local/src
ENV MC_VERSION py37_4.9.2
ENV MC_FILE Miniconda3-$MC_VERSION-Linux-x86_64.sh
# Anacaonda's repo has changed since this dockerfile was intitialy written
RUN wget -nv https://repo.anaconda.com/miniconda/$MC_FILE
RUN bash $MC_FILE -bf -p /usr
RUN rm -Rf $MC_FILE
### Disable automatic conda upgrades for predictable versioning.
RUN conda config --set auto_update_conda False
#
## Install obspy. (Matplotlib 2.0 -- the default as of 2016-01-24 and what
## obspy depends on -- with ObsPy 1.0.2 causes lots of test failures.)
RUN conda config --add channels conda-forge
RUN conda install --yes obspy=1.2.2 \
                        cartopy=0.18.0

RUN bash -c '. activate && obspy-runtests -d'
