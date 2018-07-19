load ../../../test/common

# Note: If you get output like the following (piping through cat turns of BATS
# terminal magic):
#
#  $ ./bats ../examples/spark/test.bats | cat
#  1..5
#  ok 1 spark/configure
#  ok 2 spark/start
#  [...]/test/bats.src/libexec/bats-exec-test: line 329: /tmp/bats.92406.src: No such file or directory
#  [...]/test/bats.src/libexec/bats-exec-test: line 329: /tmp/bats.92406.src: No such file or directory
#  [...]/test/bats.src/libexec/bats-exec-test: line 329: /tmp/bats.92406.src: No such file or directory
#
# that means that mpirun is starting too many processes per node (you want 1).
# One solution is to export OMPI_MCA_rmaps_base_mapping_policy= (i.e., set but
# empty).

setup () {
    scope standard
    prerequisites_ok spark
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
                    | grep -F 'scope global' \
                    | tail -1 \
                    | sed -r 's/^.+inet ([0-9.]+).+/\1/')
        # Spark workers require "mpirun". See issue #156.
        command -v mpirun >/dev/null 2>&1 || skip "mpirun not in path"
        PERNODE='mpirun -pernode'
        PERNODE_PIDFILE=/tmp/spark-pernode.pid
    else
        MASTER_IP=127.0.0.1
        PERNODE=
        PERNODE_PIDFILE=
    fi
    MASTER_URL="spark://$MASTER_IP:7077"
    MASTER_LOG="$SPARK_LOG/*master.Master*.out"
}

@test "$EXAMPLE_TAG/configure" {
    # check for restrictive umask
    run umask -S
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'u=rwx,g=,o=' ]]
    # create config
    mkdir -p "$SPARK_CONFIG"
    tee <<EOF > "$SPARK_CONFIG/spark-env.sh"
SPARK_LOCAL_DIRS=/tmp/spark
SPARK_LOG_DIR=$SPARK_LOG
SPARK_WORKER_DIR=/tmp/spark
SPARK_LOCAL_IP=127.0.0.1
SPARK_MASTER_HOST=$MASTER_IP
EOF
    MY_SECRET=$(cat /dev/urandom | tr -dc '0-9a-f' | head -c 48)
    tee <<EOF > "$SPARK_CONFIG/spark-defaults.conf"
spark.authenticate.true
spark.authenticate.secret $MY_SECRET
EOF
}

@test "$EXAMPLE_TAG/start" {
    # remove old master logs so new one has predictable name
    rm -Rf --one-file-system "$SPARK_LOG"
    # start the master
    ch-run -b "$SPARK_CONFIG" "$SPARK_IMG" -- /spark/sbin/start-master.sh
    sleep 7
    # shellcheck disable=SC2086
    cat $MASTER_LOG
    # shellcheck disable=SC2086
    grep -Fq 'New state: ALIVE' $MASTER_LOG
    # start the workers
    # shellcheck disable=SC2086
    $PERNODE ch-run -b "$SPARK_CONFIG" "$SPARK_IMG" -- \
                   /spark/sbin/start-slave.sh "$MASTER_URL" &
    if [[ -n $PERNODE ]]; then
        echo $! > "$PERNODE_PIDFILE"
    fi
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
    # shellcheck disable=SC2086
    worker_ct=$(grep -Fc 'Registering worker' $MASTER_LOG || true)
    echo "node count: $SLURM_NNODES; worker count: $worker_ct"
    [[ $worker_ct -eq "$SLURM_NNODES" ]]
}

@test "$EXAMPLE_TAG/pi" {
   run ch-run -b "$SPARK_CONFIG" "$SPARK_IMG" -- \
               /spark/bin/spark-submit --master "$MASTER_URL" \
               /spark/examples/src/main/python/pi.py 64
    echo "$output"
    [[ $status -eq 0 ]]
    # This computation converges quite slowly, so we only ask for two correct
    # digits of pi.
    [[ $output = *'Pi is roughly 3.1'* ]]
}

@test "$EXAMPLE_TAG/stop" {
    # If the workers were started with mpirun, we have to kill that prior
    # mpirun before the next one will do anything. Further, we have to abuse
    # it with SIGKILL because it doesn't quit on SIGTERM. Even further, this
    # kills all the processes started by mpirun too -- except on the node
    # where we ran mpirun.
    if [[ -n $CHTEST_MULTINODE ]]; then
        kill -9 "$(cat "$PERNODE_PIDFILE")"
    fi
    ch-run -b "$SPARK_CONFIG" "$SPARK_IMG" -- /spark/sbin/stop-slave.sh
    ch-run -b "$SPARK_CONFIG" "$SPARK_IMG" -- /spark/sbin/stop-master.sh
    sleep 2
    # Any Spark processes left?
    # (Use egrep instead of fgrep so we don't match the grep process.)
    # shellcheck disable=SC2086
    $PERNODE ps aux | ( ! grep -E '[o]rg\.apache\.spark\.deploy' )
}

@test "$EXAMPLE_TAG/hang" {
    # If there are any test processes remaining, this test will hang.
    true
}
