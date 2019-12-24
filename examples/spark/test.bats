load "${CHTEST_DIR}/common.bash"

# Note: If you get output like the following (piping through cat turns off
# BATS terminal magic):
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
    spark_dir=~/ch-spark-test.tmp  # runs before each test, so no mktemp
    spark_config=$spark_dir
    spark_log=/tmp/sparklog
    if [[ $ch_multinode ]]; then
        # Use the last non-loopback IP address. This is a barely educated
        # guess and shouldn't be relied on for real code, but hopefully it
        # works for testing.
        master_ip=$(  ip -o -f inet addr show \
                    | grep -F 'scope global' \
                    | tail -1 \
                    | sed -r 's/^.+inet ([0-9.]+).+/\1/')
        # Start Spark workers using pdsh. We would really prefer to do this
        # using srun, but that doesn't work; see issue #230.
        command -v pdsh >/dev/null 2>&1 || skip "pdsh not in path"
        pernode="pdsh -R ssh -w ${SLURM_NODELIST} -- PATH='${PATH}'"
    else
        master_ip=127.0.0.1
        pernode=
    fi
    master_url="spark://${master_ip}:7077"
    master_log="${spark_log}/*master.Master*.out"
}

@test "${ch_tag}/configure" {
    # check for restrictive umask
    run umask -S
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'u=rwx,g=,o=' ]]
    # create config
    mkdir -p "$spark_config"
    tee <<EOF > "${spark_config}/spark-env.sh"
SPARK_LOCAL_DIRS=/tmp/spark
SPARK_LOG_DIR=$spark_log
SPARK_WORKER_DIR=/tmp/spark
SPARK_LOCAL_IP=127.0.0.1
SPARK_MASTER_HOST=${master_ip}
EOF
    my_secret=$(cat /dev/urandom | tr -dc '0-9a-f' | head -c 48)
    tee <<EOF > "${spark_config}/spark-defaults.conf"
spark.authenticate.true
spark.authenticate.secret ${my_secret}
EOF
}

@test "${ch_tag}/start" {
    # remove old master logs so new one has predictable name
    rm -Rf --one-file-system "$spark_log"
    # start the master
    ch-run -b "$spark_config" "$ch_img" -- /opt/spark/sbin/start-master.sh
    sleep 7
    # shellcheck disable=SC2086
    cat $master_log
    # shellcheck disable=SC2086
    grep -Fq 'New state: ALIVE' $master_log
    # start the workers
    # shellcheck disable=SC2086
    $pernode ch-run -b "$spark_config" "$ch_img" -- \
                    /opt/spark/sbin/start-slave.sh "$master_url"
    sleep 7
}

@test "${ch_tag}/worker count" {
    # Note that in the log, each worker shows up as 127.0.0.1, which might
    # lead you to believe that all the workers started on the same (master)
    # node. However, I believe this string is self-reported by the workers and
    # is an artifact of SPARK_LOCAL_IP=127.0.0.1 above, which AFAICT just
    # tells the workers to put their web interfaces on localhost. They still
    # connect to the master and get work OK.
    [[ -z $ch_multinode ]] && SLURM_NNODES=1
    # shellcheck disable=SC2086
    worker_ct=$(grep -Fc 'Registering worker' $master_log || true)
    echo "node count: $SLURM_NNODES; worker count: ${worker_ct}"
    [[ $worker_ct -eq "$SLURM_NNODES" ]]
}

@test "${ch_tag}/pi" {
    run ch-run -b "$spark_config" "$ch_img" -- \
               /opt/spark/bin/spark-submit --master "$master_url" \
               /opt/spark/examples/src/main/python/pi.py 64
    echo "$output"
    [[ $status -eq 0 ]]
    # This computation converges quite slowly, so we only ask for two correct
    # digits of pi.
    [[ $output = *'Pi is roughly 3.1'* ]]
}

@test "${ch_tag}/stop" {
    $pernode ch-run -b "$spark_config" "$ch_img" -- /opt/spark/sbin/stop-slave.sh
    ch-run -b "$spark_config" "$ch_img" -- /opt/spark/sbin/stop-master.sh
    sleep 2
    # Any Spark processes left?
    # (Use egrep instead of fgrep so we don't match the grep process.)
    # shellcheck disable=SC2086
    $pernode ps aux | ( ! grep -E '[o]rg\.apache\.spark\.deploy' )
}

@test "${ch_tag}/hang" {
    # If there are any test processes remaining, this test will hang.
    true
}
