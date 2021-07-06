load ../common

#tmp test case

@test 'ch-run: squash' {
    scope standard

    ch_sqfs="${CH_TEST_TARDIR}/00_tiny.sqfs" #update interms of batsTmp

    run ch-run -vvv "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"mount path: /var/tmp/sqfs"* ]]
    # did it mount, run??

    # did it clean up?
    [[ -e "/var/tmp/sqfs" ]]
    rm -r /var/tmp/sqfs
}

@test 'ch-run: squash -s' {
    scope standard

    ch_sqfs="${CH_TEST_TARDIR}/00_tiny.sqfs"

    run ch-run -s /var/tmp/tmp -vvv "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"mount path: /var/tmp/tmp"* ]]
    [[ -e "/var/tmp/tmp" ]]
    rm -r /var/tmp/tmp

}
