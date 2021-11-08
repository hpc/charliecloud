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

tar=$1
img=$2
img=${img}/spark
dev=$3
conf=${HOME}/slurm-${SLURM_JOB_ID}.spark

# Make Charliecloud available (varies by site)
module purge
module load friendly-testing
module load charliecloud

# What IP address to use for master?
if [[ -z $dev ]]; then
    echo "no high-speed network device specified"
    exit 1
fi
master_ip=$(  ip -o -f inet addr show dev "$dev" \
            | sed -r 's/^.+inet ([0-9.]+).+/\1/')
master_url=spark://${master_ip}:7077
if [[ -n $master_ip ]]; then
    echo "Spark master IP: ${master_ip}"
else
    echo "no IP address for ${dev} found"
    exit 1
fi

# Unpack image
srun ch-convert -o dir "$tar" "$img"

# Make Spark configuration
mkdir "$conf"
chmod 700 "$conf"
cat <<EOF > "${conf}/spark-env.sh"
SPARK_LOCAL_DIRS=/tmp/spark
SPARK_LOG_DIR=/tmp/spark/log
SPARK_WORKER_DIR=/tmp/spark
SPARK_LOCAL_IP=127.0.0.1
SPARK_MASTER_HOST=${master_ip}
JAVA_HOME=/usr/lib/jvm/default-java/
EOF
mysecret=$(cat /dev/urandom | tr -dc '0-9a-f' | head -c 48)
cat <<EOF > "${conf}/spark-defaults.sh"
spark.authenticate true
spark.authenticate.secret $mysecret
EOF
chmod 600 "${conf}/spark-defaults.sh"

# Start the Spark master
ch-run -b "$conf" "$img" -- /spark/sbin/start-master.sh
sleep 10
tail -7 /tmp/spark/log/*master*.out
grep -Fq 'New state: ALIVE' /tmp/spark/log/*master*.out

# Start the Spark workers
srun sh -c "   ch-run -b '${conf}' '${img}' -- \
                      /spark/sbin/start-slave.sh ${master_url} \
            && sleep infinity" &
sleep 10
grep -F worker /tmp/spark/log/*master*.out
tail -3 /tmp/spark/log/*worker*.out

# Compute pi
ch-run -b "$conf" "$img" -- \
       /spark/bin/spark-submit --master "$master_url" \
       /spark/examples/src/main/python/pi.py 1024
# Let Slurm kill the workers and master
