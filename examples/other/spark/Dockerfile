# ch-test-scope: standard
FROM debian:stretch

# Install needed OS packages.
RUN    apt-get update \
    && apt-get install -y less openjdk-8-jre-headless procps python wget \
    && rm -rf /var/lib/apt/lists/*

# We want ch-ssh
RUN touch /usr/bin/ch-ssh

# Download and install Spark.
#
# Updated to spark-2.4.4

ENV URLPATH https://www.apache.org/dist/spark/spark-2.4.4/
ENV DIR spark-2.4.4-bin-hadoop2.7
ENV TAR $DIR.tgz
# [2]: https://community.cloudera.com/t5/Advanced-Analytics-Apache-Spark/Spark-displays-SQLException-when-Hive-not-installed/td-p/37954
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
