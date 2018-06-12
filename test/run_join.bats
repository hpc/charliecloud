load common

setup () {
    scope quick
}

ipc_clean_p () {
    [[ 0 = $(ipc_count) ]]
}

ipc_count () {
    find /dev/shm -maxdepth 1 -name '*ch-run*' | wc -l
}

joined_ok () {
    # parameters
    proc_ct_total=$1  # total number of processes
    peer_ct_node=$2   # size of each peer group (peers per node)
    namespace_ct=$3   # number of different namespace IDs
    status=$4         # exit status
    output="$5"       # output
    echo "$output"
    # exit success
    printf '  exit status: ' 1>&2
    if [[ $status -eq 0 ]]; then
        printf 'ok\n' 1>&2
    else
        printf 'fail (%d)\n' $status 1>&2
        return 1
    fi
    # number of processes
    printf '  process count; expected %d: ' $proc_ct_total 1>&2
    proc_ct_found=$(echo "$output" | egrep -c 'join: 1 [0-9]+ [0-9a-z]+')
    if [[ $proc_ct_total -eq $proc_ct_found ]]; then
        printf 'ok\n'
    else
        printf 'fail (%d)\n' $proc_ct_found 1>&2
        return 1
    fi
    # number of peers
    printf '  peer group size; expected %d: ' $peer_ct_node 1>&2
    peer_cts=$(  echo "$output" \
               | sed -rn 's/^ch-run\[[0-9]+\]: join: 1 ([0-9]+) .+$/\1/p')
    peer_ct_found=$(echo "$peer_cts" | sort -u)
    peer_cts_found=$(echo "$peer_ct_found" | wc -l)
    if [[ $peer_cts_found -ne 1 ]]; then
        printf 'fail (%d different counts reported)\n' $peer_cts_found 1>&2
        return 1
    fi
    if [[ $peer_ct_found -eq $peer_ct_node ]]; then
        printf 'ok\n' 1>&2
    else
        printf 'fail (%d)\n' $peer_ct_found 1>&2
        return 1
    fi
    # correct number of namespace IDs
    for i in $(ls /proc/self/ns); do
        printf '  namespace ID count; expected %d: %s: ' $namespace_ct $i 1>&2
        namespace_ct_found=$(  echo "$output" \
                             | egrep "^/proc/self/ns/$i:" \
                             | sort -u \
                             | wc -l)
        if [[ $namespace_ct -eq $namespace_ct_found ]]; then
            printf 'ok\n' 1>&2
        else
            printf 'fail (%d)\n' $namespace_ct_found 1>&2
            return 1
        fi
    done
}

# Unset environment variables that might be used.
unset_vars () {
    unset OMPI_COMM_WORLD_LOCAL_SIZE
    unset SLURM_CPUS_ON_NODE
    unset SLURM_STEP_ID
    unset SLURM_STEP_TASKS_PER_NODE
}


@test 'ch-run --join: one peer, direct launch' {
    scope standard
    unset_vars
    ipc_clean_p

    # --join-ct
    run ch-run -v --join-ct=1 $CHTEST_IMG -- /test/printns
    joined_ok 1 1 1 $status "$output"
    r='join: 1 1 [0-9]+ '   # status from getppid(2) is all digits
    [[ $output =~ $r ]]
    [[ $output =~ 'join: peer group size from command line' ]]
    ipc_clean_p

    # join count from an environment variable
    SLURM_CPUS_ON_NODE=1 run ch-run -v --join $CHTEST_IMG -- /test/printns
    joined_ok 1 1 1 $status "$output"
    [[ $output =~ 'join: peer group size from SLURM_CPUS_ON_NODE' ]]
    ipc_clean_p

    # join count from an environment variable with extra goop
    SLURM_CPUS_ON_NODE=1foo ch-run --join $CHTEST_IMG -- /test/printns
    joined_ok 1 1 1 $status "$output"
    [[ $output =~ 'join: peer group size from SLURM_CPUS_ON_NODE' ]]
    ipc_clean_p

    # join tag
    run ch-run -v --join-ct=1 --join-tag=foo $CHTEST_IMG -- /test/printns
    joined_ok 1 1 1 $status "$output"
    [[ $output =~ 'join: 1 1 foo' ]]
    [[ $output =~ 'join: peer group tag from command line' ]]
    ipc_clean_p
    SLURM_STEP_ID=bar run ch-run -v --join-ct=1 $CHTEST_IMG -- /test/printns
    joined_ok 1 1 1 $status "$output"
    [[ $output =~ 'join: 1 1 bar' ]]
    [[ $output =~ 'join: peer group tag from SLURM_STEP_ID' ]]
    ipc_clean_p
}

@test 'ch-run --join: two peers, direct launch' {
    scope standard
    unset_vars
    ipc_clean_p
    outfiles="$BATS_TMPDIR/join.?.*"
    rm -f $outfiles

    # first peer (winner)
    ch-run -v --join-ct=2 --join-tag=foo $CHTEST_IMG -- \
           /test/printns 5 $BATS_TMPDIR/join.1.ns \
           >& $BATS_TMPDIR/join.1.err &
    sleep 1
    cat $BATS_TMPDIR/join.1.err
    cat $BATS_TMPDIR/join.1.ns
      fgrep -q 'join: 1 2' $BATS_TMPDIR/join.1.err
      fgrep -q 'join: I won' $BATS_TMPDIR/join.1.err
    ! fgrep -q 'join: cleaning up IPC' $BATS_TMPDIR/join.1.err

    # IPC resources present?
    test -e /dev/shm/ch-run_foo
    test -e /dev/shm/sem.ch-run_foo

    # second peer (loser)
    run ch-run -v --join-ct=2 --join-tag=foo $CHTEST_IMG -- \
               /test/printns 0 $BATS_TMPDIR/join.2.ns \
    echo "$output"
    [[ $status -eq 0 ]]
    cat $BATS_TMPDIR/join.2.ns
      echo "$output" | fgrep -q 'join: 1 2'
      echo "$output" | fgrep -q 'join: winner pid:'
      echo "$output" | fgrep -q 'join: cleaning up IPC'

    # same namespaces?
    for i in $(ls /proc/self/ns); do
        [[ 1 = $(  cat $BATS_TMPDIR/join.?.ns \
                 | egrep "^/proc/self/ns/$i:" | uniq | wc -l) ]]
    done

    ipc_clean_p
}

@test 'ch-run --join: three peers, direct launch' {
    scope standard
    unset_vars
    ipc_clean_p
    outfiles="$BATS_TMPDIR/join.?.*"
    rm -f $outfiles

    # first peer (winner)
    ch-run -v --join-ct=3 --join-tag=foo $CHTEST_IMG -- \
           /test/printns 5 $BATS_TMPDIR/join.1.ns \
           >& $BATS_TMPDIR/join.1.err &
    sleep 1
    cat $BATS_TMPDIR/join.1.err
    cat $BATS_TMPDIR/join.1.ns
      fgrep -q 'join: 1 3' $BATS_TMPDIR/join.1.err
      fgrep -q 'join: I won' $BATS_TMPDIR/join.1.err
      fgrep -q 'join: 2 peers left' $BATS_TMPDIR/join.1.err
    ! fgrep -q 'join: cleaning up IPC' $BATS_TMPDIR/join.1.err

    # second peer (loser, no cleanup)
    ch-run -v --join-ct=3 --join-tag=foo $CHTEST_IMG -- \
           /test/printns 0 $BATS_TMPDIR/join.2.ns \
           >& $BATS_TMPDIR/join.2.err &
    sleep 1
    cat $BATS_TMPDIR/join.2.err
    cat $BATS_TMPDIR/join.2.ns
      fgrep -q 'join: 1 3' $BATS_TMPDIR/join.2.err
      fgrep -q 'join: winner pid:' $BATS_TMPDIR/join.2.err
      fgrep -q 'join: 1 peers left' $BATS_TMPDIR/join.2.err
    ! fgrep -q 'join: cleaning up IPC' $BATS_TMPDIR/join.2.err

    # IPC resources present?
    test -e /dev/shm/ch-run_foo
    test -e /dev/shm/sem.ch-run_foo

    # third peer (loser, cleanup)
    ch-run -v --join-ct=3 --join-tag=foo $CHTEST_IMG -- \
           /test/printns 0 $BATS_TMPDIR/join.3.ns \
           >& $BATS_TMPDIR/join.3.err &
    cat $BATS_TMPDIR/join.3.err
    cat $BATS_TMPDIR/join.3.ns
      fgrep -q 'join: 1 3' $BATS_TMPDIR/join.3.err
      fgrep -q 'join: winner pid:' $BATS_TMPDIR/join.3.err
      fgrep -q 'join: 0 peers left' $BATS_TMPDIR/join.3.err
      fgrep -q 'join: cleaning up IPC' $BATS_TMPDIR/join.3.err

    # same namespaces?
    for i in $(ls /proc/self/ns); do
        [[ 1 = $(  cat $BATS_TMPDIR/join.?.ns \
                 | egrep "^/proc/self/ns/$i:" | uniq | wc -l) ]]
    done

    ipc_clean_p
}

@test 'ch-run --join: multiple peers, framework launch' {
    scope standard
    multiprocess_ok
    ipc_clean_p

    # Two peers, one node. Should be one of each of the namespaces. Make sure
    # everyone chdir(2)s properly.
    run $MPIRUN_2_1NODE ch-run -v --join --cd /test $CHTEST_IMG -- ./printns 2
    ipc_clean_p
    joined_ok 2 2 1 $status "$output"

    # One peer per core across the allocation. Should be $CHTEST_NODES of each
    # of the namespaces.
    run $MPIRUN_CORE ch-run -v --join $CHTEST_IMG -- /test/printns 4
    joined_ok $CHTEST_CORES_TOTAL $CHTEST_CORES_NODE $CHTEST_NODES \
              $status "$output"
    ipc_clean_p
}

@test 'ch-run --join: peer group size errors' {
    scope standard
    unset_vars

    # join count negative
    run ch-run --join-ct=-1 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join: no valid peer group size found' ]]
    SLURM_CPUS_ON_NODE=-1 run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join: no valid peer group size found' ]]

    # join count zero
    run ch-run --join-ct=0 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join: no valid peer group size found' ]]
    SLURM_CPUS_ON_NODE=0 run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join: no valid peer group size found' ]]

    # --join but no join count
    run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join: no valid peer group size found' ]]

    # join count no digits
    run ch-run --join-ct=a $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join-ct: no digits found' ]]
    SLURM_CPUS_ON_NODE=a run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'SLURM_CPUS_ON_NODE: no digits found' ]]

    # join count empty string
    run ch-run --join-ct='' $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join-ct: no digits found' ]]
    SLURM_CPUS_ON_NODE=-1 run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join: no valid peer group size found' ]]

    # --join-ct digits followed by extra goo (OK from environment variable)
    run ch-run --join-ct=1a $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join-ct: extra characters after digits' ]]

    # Regex for out-of-range error.
    range_re='.*: .*out of range'

    # join count above INT_MAX
    run ch-run --join-ct=2147483648 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ $range_re ]]
    SLURM_CPUS_ON_NODE=2147483648 \
        run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ $range_re ]]

    # join count below INT_MIN
    run ch-run --join-ct=-2147483649 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ $range_re ]]
    SLURM_CPUS_ON_NODE=-2147483649 \
        run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ $range_re ]]

    # join count above LONG_MAX
    run ch-run --join-ct=9223372036854775808 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ $range_re ]]
    SLURM_CPUS_ON_NODE=9223372036854775808 \
        run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ $range_re ]]

    # join count below LONG_MIN
    run ch-run --join-ct=-9223372036854775809 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ $range_re ]]
    SLURM_CPUS_ON_NODE=-9223372036854775809 \
        run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ $range_re ]]
}

@test 'ch-run --join: peer group tag errors' {
    scope standard
    unset_vars

    # Use a join count of 1 throughout.
    export SLURM_CPUS_ON_NODE=1

    # join tag empty string
    run ch-run --join-tag='' $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join: peer group tag cannot be empty string' ]]
    SLURM_STEP_ID='' run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'join: peer group tag cannot be empty string' ]]
}
