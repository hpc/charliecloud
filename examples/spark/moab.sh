#!/bin/bash
# MSUB -l walltime=0:10:00

# Run in directory where the tarball is. Output will go to same place.
# Needs Spark configuration in ~/sparkconf.

set -e

TAG=spark
IMAGE=/tmp/$TAG

mpirun -pernode ch-tar2dir ./$USER.$TAG.tar.gz $IMAGE > /dev/null

# start Spark cluster
MASTER_IP=$(sh -c 'source ~/sparkconf/spark-env.sh && echo $SPARK_LOCAL_IP')
MASTER_URL="spark://$MASTER_IP:7077"
echo "master: $MASTER_URL"
ch-run -d ~/sparkconf /tmp/spark -- /spark/sbin/start-master.sh
mpirun -pernode ch-run -d ~/sparkconf /tmp/spark -- \
  /spark/sbin/start-slave.sh $MASTER_URL &
sleep 10  # wait for workers to boot

# run our job
ch-run -d ~/sparkconf /tmp/spark -- \
  /spark/bin/spark-submit --master $MASTER_URL \
  /spark/examples/src/main/python/pi.py 1024

# shut down Spark cluster
mpirun -pernode ch-run -d ~/sparkconf /tmp/spark /spark/sbin/stop-slave.sh
ch-run -d ~/sparkconf /tmp/spark /spark/sbin/stop-master.sh
sleep 2   # wait for things to finish exiting
