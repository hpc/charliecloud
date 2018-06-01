load common

setup () {
    scope quick
}

# Unset environment variables that might be used.
unset_vars () {
    unset OMPI_COMM_WORLD_LOCAL_SIZE
    unset SLURM_CPUS_ON_NODE
    unset SLURM_STEP_ID
    unset SLURM_STEP_TASKS_PER_NODE
}


@test 'ch-run --join: peer group size errors' {
    scope quick
    unset_vars

    # join count negative
    run ch-run --join-ct=-1 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join: no valid peer group size found' ]]
    SLURM_CPUS_ON_NODE=-1 run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join: no valid peer group size found' ]]

    # join count zero
    run ch-run --join-ct=0 $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join: no valid peer group size found' ]]
    SLURM_CPUS_ON_NODE=0 run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join: no valid peer group size found' ]]

    # --join but no join count
    run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join: no valid peer group size found' ]]

    # join count no digits
    run ch-run --join-ct=a $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join-ct: no digits found' ]]
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
    [[ $output =~ '--join: no valid peer group size found' ]]

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
    scope quick
    unset_vars

    # Use a join count of 1 throughout.
    export SLURM_CPUS_ON_NODE=1

    # join tag empty string
    run ch-run --join-tag='' $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join: peer group tag cannot be empty string' ]]
    SLURM_STEP_ID='' run ch-run --join $CHTEST_IMG -- true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--join: peer group tag cannot be empty string' ]]
}
