load ../../test/common

setup () {
    umask 0077
    SPARK_IMG=$IMGDIR/spark
    SPARK_DIR=$BATS_TMPDIR/spark.tmp
    SPARK_CONFIG=$SPARK_DIR
    if [[ -n $CHTEST_MULTINODE ]]; then
        false  # unimplemented
        MPIRUN='mpirun -pernode'
    else
        MASTER_IP=127.0.0.1
        MPIRUN=
    fi
    MASTER_URL="spark://$MASTER_IP:7077"
}

@test "$EXAMPLE_TAG/configure" {
    # check for restrictive umask
    run umask -S
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'u=rwx,g=,o=' ]]
    # create config
    mkdir -p $SPARK_CONFIG
    tee <<EOF > $SPARK_CONFIG/spark-env.sh
SPARK_LOCAL_DIRS=/tmp
SPARK_LOG_DIR=/mnt/0/log
SPARK_WORKER_DIR=/tmp
SPARK_LOCAL_IP=$MASTER_IP
SPARK_MASTER_HOST=$MASTER_IP
EOF
    MY_SECRET=$(cat /dev/urandom | tr -dc 'a-z' | head -c 48)
    tee <<EOF > $SPARK_CONFIG/spark-defaults.conf
spark.authenticate.true
spark.authenticate.secret $MY_SECRET
EOF
}

@test "$EXAMPLE_TAG/start" {
    # remove old logs so new log has predictable name
    rm -Rf $SPARK_DIR/log
    # start the master
    ch-run -d $SPARK_CONFIG $SPARK_IMG -- /spark/sbin/start-master.sh
    sleep 2  # race condition here somehow?
    cat $SPARK_DIR/log/*master.Master*.out
    fgrep -q 'New state: ALIVE' $SPARK_DIR/log/*master.Master*.out
    # start the workers
    $MPIRUN ch-run -d $SPARK_CONFIG $SPARK_IMG -- \
                   /spark/sbin/start-slave.sh $MASTER_URL &
    sleep 5
}

@test "$EXAMPLE_TAG/pi" {
    run ch-run -d $SPARK_CONFIG $SPARK_IMG -- \
               /spark/bin/spark-submit --master $MASTER_URL \
               /spark/examples/src/main/python/pi.py 64
    echo "$output"
    [[ $status -eq 0 ]]
    # This computation converges quite slowly, so we only ask for two correct
    # digits of pi.
    [[ $output =~ 'Pi is roughly 3.1' ]]
}

@test "$EXAMPLE_TAG/stop" {
    $MPIRUN ch-run -d $SPARK_CONFIG $SPARK_IMG -- /spark/sbin/stop-slave.sh
    ch-run -d $SPARK_CONFIG $SPARK_IMG -- /spark/sbin/stop-master.sh
    sleep 2
}
