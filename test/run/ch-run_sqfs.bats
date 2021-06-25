load ../common

@test 'ch-run: squash' {
    # sqfs is located in /var/tmp/tar
    scope standard

    ch_sqfs="/var/tmp/tar/00_tiny.sqfs" #update interms of batsTmp

    run ch-run -vvv "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"mount path: /var/tmp/00_tiny"* ]]
    [[ $output = *"unmounting: /var/tmp/00_tiny"* ]]
    # idk how to actually test that it is doing this??..

    run ch-run "$ch_sqfs" -- echo "hellO"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "hello" ]]

}
