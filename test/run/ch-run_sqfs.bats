load ../common

#tmp test case

@test 'ch-run: squash' {
    scope standard

    ch_sqfs="${CH_TEST_TARDIR}/00_tiny.sqfs"
    ch_mnt="/var/tmp/${USER}.ch/mnt"

    run ch-run -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: ${ch_mnt}"* ]]

    [[ -d ${ch_mnt} ]]
    rmdir "${ch_mnt}"

    # -s option
    run ch-run -s /var/tmp/tmp -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: /var/tmp/tmp"* ]]
    [[ -d "/var/tmp/tmp" ]]
    rmdir /var/tmp/tmp

    # -s with non-sqfs img
    run ch-run -s /var/tmp/tmp -v "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"WARNING: invalid option -s, --squashmnt"* ]]
    [[ $output = *"newroot: ${ch_timg}"* ]]

    # only create 1 directory
    run ch-run -s /var/tmp/sq -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: /var/tmp/sq"* ]]
    [[ -d "/var/tmp/sq" ]]
    rmdir /var/tmp/sq
}

@test 'ch-run: squash errors' {
    scope standard

    ch_sqfs="${CH_TEST_TARDIR}"/00_tiny.sqfs

    # empty mount point
    run ch-run --squashmt= -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]] # exits with status of 139
    [[ $output = *"mount point can't be empty"* ]]

    # parent dir doesn't exist
    run ch-run -s /var/tmp/sq/mnt -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]] # exits with status of 139
    [[ $output = *"failed to create: /var/tmp/sq/mnt"* ]]
    [[ ! -e "/var/tmp/sq/mnt" ]]

    # input is file but not sqfs
    run ch-run -v Build.missing -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"invalid input type"* ]]

    # input has same magic number but is broken
    sq_tmp="${CH_TEST_TARDIR}"/tmp.sqfs
    # copy over magic number from sqfs to broken sqfs
    dd if="$ch_sqfs" of="$sq_tmp" conv=notrunc bs=1 count=4
    run ch-run -vvv "$sq_tmp" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *"Magic Number: 73717368"* ]]
    [[ $output = *"failed to open ${sq_tmp}"* ]]
    rm "${sq_tmp}"
}
