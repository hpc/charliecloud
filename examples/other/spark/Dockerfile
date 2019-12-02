# ch-test-scope: standard
FROM debian:stretch

# Install needed OS packages.
RUN    apt-get update \
    && apt-get install -y less openjdk-8-jre-headless procps python wget \
    && rm -rf /var/lib/apt/lists/*

# We want ch-ssh
RUN touch /usr/bin/ch-ssh

# Download and install Spark.
# We aren't using SPARK_NO_DAEMONIZE to make sure can deakwith daemonized spark. 
# Spark is installed to /opt/spark which is spark's new default location
# We disapprove of spark's master/slave terminology, but it's what the scripts are called

ENV URLPATH https://www.apache.org/dist/spark/spark-2.4.4/
ENV DIR spark-2.4.4-bin-hadoop2.7
ENV TAR $DIR.tgz
RUN wget -nv $URLPATH/$TAR
RUN tar xf $TAR && mv $DIR /opt/spark && rm $TAR

# Very basic default configuration, to make it run and not do anything stupid.
RUN printf '\
SPARK_LOCAL_IP=127.0.0.1\n\
SPARK_LOCAL_DIRS=/tmp\n\
SPARK_LOG_DIR=/tmp\n\
SPARK_WORKER_DIR=/tmp\n\
' > /opt/spark/conf/spark-env.sh

# Move config to /mnt/0 so we can provide a different config if we want
RUN    mv /opt/spark/conf /mnt/0 \
    && ln -s /mnt/0 /opt/spark/conf
