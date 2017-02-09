load ../../test/common

# FIXME: This test works as part of "make test" but not when run directly with
# BATS. For example (piping through cat turns of BATS terminal magic):
#
#  $ ./bats ../examples/spark/test.bats | cat
#  1..5
#  ok 1 spark/configure
#  ok 2 spark/start
#  [...]/test/bats.src/libexec/bats-exec-test: line 329: /tmp/bats.92406.src: No such file or directory
#  [...]/test/bats.src/libexec/bats-exec-test: line 329: /tmp/bats.92406.src: No such file or directory
#  [...]/test/bats.src/libexec/bats-exec-test: line 329: /tmp/bats.92406.src: No such file or directory
#
# "spark/worker count" then hangs. Something in "spark/start" is deleting
# /tmp/bats.92406.src. To recover, one must control-C and kill the Spark
# master manually.

setup () {
    umask 0077
    SPARK_IMG=$IMGDIR/spark
    SPARK_DIR=~/ch-spark-test.tmp  # runs before each test, so no mktemp
    SPARK_CONFIG=$SPARK_DIR
    SPARK_LOG=/tmp/sparklog
    if [[ $CHTEST_MULTINODE ]]; then
        # Use the last non-loopback IP address. This is a barely educated
        # guess and shouldn't be relied on for real code, but hopefully it
        # works for testing.
        MASTER_IP=$(  ip -o -f inet addr show \
                    | fgrep 'scope global' \
                    | tail -1 \
                    | sed -r 's/^.+inet ([0-9.]+).+/\1/')
        MPIRUN='mpirun -pernode'
    else
        MASTER_IP=127.0.0.1
        MPIRUN=
    fi
    MASTER_URL="spark://$MASTER_IP:7077"
    MASTER_LOG=$SPARK_LOG/*master.Master*.out
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
SPARK_LOCAL_DIRS=/tmp/spark
SPARK_LOG_DIR=$SPARK_LOG
SPARK_WORKER_DIR=/tmp/spark
SPARK_LOCAL_IP=127.0.0.1
SPARK_MASTER_HOST=$MASTER_IP
EOF
    MY_SECRET=$(cat /dev/urandom | tr -dc 'a-z' | head -c 48)
    tee <<EOF > $SPARK_CONFIG/spark-defaults.conf
spark.authenticate.true
spark.authenticate.secret $MY_SECRET
EOF
}

@test "$EXAMPLE_TAG/start" {
    # remove old master logs so new one has predictable name
    rm -Rf $SPARKLOG
    # start the master
    ch-run -d $SPARK_CONFIG $SPARK_IMG -- /spark/sbin/start-master.sh
    sleep 2  # race condition here somehow?
    cat $MASTER_LOG
    fgrep -q 'New state: ALIVE' $MASTER_LOG
    # start the workers
    $MPIRUN ch-run -d $SPARK_CONFIG $SPARK_IMG -- \
                   /spark/sbin/start-slave.sh $MASTER_URL &
    sleep 7
}

@test "$EXAMPLE_TAG/worker count" {
    # Note that in the log, each worker shows up as 127.0.0.1, which might
    # lead you to believe that all the workers started on the same (master)
    # node. However, I believe this string is self-reported by the workers and
    # is an artifact of SPARK_LOCAL_IP=127.0.0.1 above, which AFAICT just
    # tells the workers to put their web interfaces on localhost. They still
    # connect to the master and get work OK.
    [[ -z $CHTEST_MULTINODE ]] && SLURM_NNODES=1
    worker_ct=$(fgrep -c 'Registering worker' $MASTER_LOG)
    echo "node count: $SLURM_NNODES; worker count: $worker_ct"
    [[ $worker_ct -eq $SLURM_NNODES ]]
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
