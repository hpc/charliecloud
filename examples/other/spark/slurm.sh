#!/bin/bash
#SBATCH --time=0:10:00

# Run an example non-interactive Spark computation. Requires three arguments:
#
#   1. Image tarball
#   2. Directory in which to unpack tarball
#   3. High-speed network interface name
#
# Example:
#
#   $ sbatch slurm.sh /scratch/spark.tar.gz /var/tmp ib0
#
# Spark configuration will be generated in ~/slurm-$SLURM_JOB_ID.spark; any
# configuration already there will be clobbered.

set -e

if [[ -z $SLURM_JOB_ID ]]; then
    echo "not running under Slurm" 1>&2
    exit 1
fi

TAR="$1"
IMGDIR="$2"
IMG="$IMGDIR/spark"
DEV="$3"
CONF="$HOME/slurm-$SLURM_JOB_ID.spark"

# Make Charliecloud available (varies by site)
module purge
module load friendly-testing
module load charliecloud

# What IP address to use for master?
if [[ -z $DEV ]]; then
    echo "no high-speed network device specified"
    exit 1
fi
MASTER_IP=$(  ip -o -f inet addr show dev "$DEV" \
            | sed -r 's/^.+inet ([0-9.]+).+/\1/')
MASTER_URL=spark://$MASTER_IP:7077
if [[ -n $MASTER_IP ]]; then
    echo "Spark master IP: $MASTER_IP"
else
    echo "no IP address for $DEV found"
    exit 1
fi

# Unpack image
srun ch-tar2dir "$TAR" "$IMGDIR"

# Make Spark configuration
mkdir "$CONF"
chmod 700 "$CONF"
cat <<EOF > "$CONF/spark-env.sh"
SPARK_LOCAL_DIRS=/tmp/spark
SPARK_LOG_DIR=/tmp/spark/log
SPARK_WORKER_DIR=/tmp/spark
SPARK_LOCAL_IP=127.0.0.1
SPARK_MASTER_HOST=$MASTER_IP
EOF
MYSECRET=$(cat /dev/urandom | tr -dc '0-9a-f' | head -c 48)
cat <<EOF > "$CONF/spark-defaults.sh"
spark.authenticate true
spark.authenticate.secret $MYSECRET
EOF
chmod 600 "$CONF/spark-defaults.sh"

# Start the Spark master
ch-run -b "$CONF" "$IMG" -- /spark/sbin/start-master.sh
sleep 10
tail -7 /tmp/spark/log/*master*.out
grep -Fq 'New state: ALIVE' /tmp/spark/log/*master*.out

# Start the Spark workers
srun sh -c "   ch-run -b '$CONF' '$IMG' -- \
                      /spark/sbin/start-slave.sh $MASTER_URL \
            && sleep infinity" &
sleep 10
grep -F worker /tmp/spark/log/*master*.out
tail -3 /tmp/spark/log/*worker*.out

# Compute pi
ch-run -b "$CONF" "$IMG" -- \
       /spark/bin/spark-submit --master "$MASTER_URL" \
       /spark/examples/src/main/python/pi.py 1024

# Let Slurm kill the workers and master
