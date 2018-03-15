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
# We're staying on Spark 2.0 because 2.1.0 introduces Hive for metadata
# handling somehow [1]. Data for this goes in $CWD by default, which is / and
# not writeable in Charliecloud containers. So you get thousands of lines of
# stack trace from pyspark. Workarounds exist, including cd to /tmp first or
# configure hive-site.xml [2], but I'm not willing to put up with that crap
# for demo purposes. Maybe it will be fixed in a 2.1 point release.
#
# [1]: http://spark.apache.org/docs/latest/sql-programming-guide.html#upgrading-from-spark-sql-20-to-21
# [2]: https://community.cloudera.com/t5/Advanced-Analytics-Apache-Spark/Spark-displays-SQLException-when-Hive-not-installed/td-p/37954
ENV URLPATH http://d3kbcqa49mib13.cloudfront.net
ENV DIR spark-2.0.2-bin-hadoop2.7
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
