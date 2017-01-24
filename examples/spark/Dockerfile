FROM debian:jessie

# Install needed OS packages.
RUN    apt-get update \
    && apt-get install -y less openjdk-7-jre-headless python wget \
    && rm -rf /var/lib/apt/lists/*

# We want ch-ssh
RUN touch /usr/bin/ch-ssh

# Download and install Spark
ENV URLPATH http://d3kbcqa49mib13.cloudfront.net
ENV DIR spark-2.1.0-bin-hadoop2.7
ENV TAR $DIR.tgz
RUN wget -nv $URLPATH/$TAR
RUN tar xf $TAR && mv $DIR spark && rm $TAR

# Very basic default configuration, to make it run and not do anything stupid.
RUN printf '\
SPARK_LOCAL_IP=127.0.0.1\n\
SPARK_LOCAL_DIRS=/tmp\n\
SPARK_LOG_DIR=/tmp\n\
SPARK_WORKER_DIR=/tmp\n\
' > /spark/conf/spark-env.sh

# Move config to /mnt/0 so we can provide a different config if we want
RUN    mv /spark/conf /mnt/0 \
    && ln -s /mnt/0 /spark/conf
