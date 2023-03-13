# ch-test-scope: full
#
# Use Buster because Stretch JRE install fails with:
#
#   tempnam() is so ludicrously insecure as to defy implementation.
#   tempnam: Cannot allocate memory
#   dpkg: error processing package openjdk-8-jre-headless:amd64 (--configure):
#    subprocess installed post-installation script returned error exit status 1

FROM debian:buster

ARG DEBIAN_FRONTEND=noninteractive
# Install needed OS packages.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
                    default-jre-headless \
                    less \
                    procps \
                    python3 \
                    wget \
 && rm -rf /var/lib/apt/lists/*

# We want ch-ssh
RUN touch /usr/bin/ch-ssh

# Download and install Spark. Notes:
#
# 1. We aren’t using SPARK_NO_DAEMONIZE to make sure can deal with daemonized
#    applications.
#
# 2. Spark is installed to /opt/spark, which is Spark’s new default location.
ARG URLPATH=https://archive.apache.org/dist/spark/spark-3.2.0/
ARG DIR=spark-3.2.0-bin-hadoop3.2
ARG TAR=$DIR.tgz
RUN wget -nv $URLPATH/$TAR \
 && tar xf $TAR \
 && mv $DIR /opt/spark \
 && rm $TAR

# Very basic default configuration, to make it run and not do anything stupid.
RUN printf '\
SPARK_LOCAL_IP=127.0.0.1\n\
SPARK_LOCAL_DIRS=/tmp\n\
SPARK_LOG_DIR=/tmp\n\
SPARK_WORKER_DIR=/tmp\n\
' > /opt/spark/conf/spark-env.sh

# Move config to /mnt/0 so we can provide a different config if we want
RUN mv /opt/spark/conf /mnt/0 \
 && ln -s /mnt/0 /opt/spark/conf
