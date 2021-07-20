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
}

@test 'ch-run: squash -s' {
    scope standard

    ch_sqfs="${CH_TEST_TARDIR}/00_tiny.sqfs"

    run ch-run -s /var/tmp/tmp -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: /var/tmp/tmp"* ]]
    [[ -d "/var/tmp/tmp" ]]
    rmdir /var/tmp/tmp

    # -s with non-sqfs img **should it fail? no but warning*******
    run ch-run -s /var/tmp/tmp -v "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"WARNING: invalid option -s, --squashmnt"* ]]
    [[ $output = *"newroot: ${ch_timg}"* ]]

}

@test 'ch-run: squash dir make' {
    scope standard

    ch_sqfs="${CH_TEST_TARDIR}/00_tiny.sqfs"

    # only create 1 directory
    run ch-run -s /var/tmp/sq -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: /var/tmp/sq"* ]]
    [[ -d "/var/tmp/sq" ]]
    rmdir /var/tmp/sq

    # parent dir doesn't exist
    run ch-run -s /var/tmp/sq/mnt -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]] # exits with status of 139
    [[ $output = *"failed to create: /var/tmp/sq/mnt"* ]]
    [[ ! -e "/var/tmp/sq/mnt" ]]
}

@test 'ch-run: squash fails' {
    scope standard

    # input is file but not sqfs
    run ch-run -v Build.missing -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"invalid input type"* ]]

    # input has same magic number but is broken
    ch_sqfs="${CH_TEST_TARDIR}"/tmp.sqfs
    # copy over magic number from sqfs to broken sqfs
    dd if="$CH_TEST_TARDIR"/00_tiny.sqfs of="$ch_sqfs" conv=notrunc bs=1 count=4
    run ch-run -vvv "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *"Magic Number: 73717368"* ]]
    [[ $output = *"failed to open ${ch_sqfs}"* ]]
    rm "${ch_sqfs}"
}
