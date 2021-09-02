load ../common

#tmp test case
test_sq=$(cat ../bin/config.h | grep HAVE_LIBSQUASHFUSE)

@test 'ch-run: squash' {
    scope standard
    [[ $test_sq = *"#undef"* ]] && skip 'no squashfuse'

    ch_sqfs="${CH_TEST_TARDIR}/00_tiny.sqfs"
    ch_mnt="/var/tmp/${USER}.ch/mnt"

    run ch-run -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"using default mount point: ${ch_mnt}"* ]]

    [[ -d ${ch_mnt} ]]
    rmdir "${ch_mnt}"

    # -s option
    mountpt="${BATS_TMPDIR}/sqfs_tmpdir" #fix later
    mkdir "$mountpt"
    run ch-run -m "$mountpt" -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: ${mountpt}"* ]]

    # -s with non-sqfs img
    run ch-run -m "$mountpt" -v "$ch_timg" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"warning: --mount invalid with directory image, ignoring"* ]]
    [[ $output = *"newroot: ${ch_timg}"* ]]

    # only create 1 directory
    run ch-run -m "$mountpt" -v "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"newroot: ${mountpt}"* ]]
    [[ -d "$mountpt" ]]
    rmdir "$mountpt"

   # create multiple directory w/ default
   # **** tmp test ************
   # rm -r /var/tmp/vm-user.ch
   # run ch-run "$ch_sqfs" -- /bin/true
   # echo "$output"
   # [[ $status -eq 0 ]]
   # [[ -d "$ch_mnt" ]]
}

@test 'ch-run: squash errors' {
    scope standard
    [[ $test_sq = *"#undef"* ]] && skip 'no squashfuse'

    ch_sqfs="${CH_TEST_TARDIR}"/00_tiny.sqfs

    # empty mount point
    run ch-run --mount= "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]] # exits with status of 139
    [[ $output = *"mount point can't be empty"* ]]

    # parent dir doesn't exist
    mountpt="${BATS_TMPDIR}/sq/mnt"
    run ch-run -m "$mountpt" "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]] # exits with status of 139
    [[ $output = *"can't stat mount point: ${mountpt}"* ]]

    # mount point contains a file, can't opendir but shouldn't make it
    run ch-run -m /var/tmp/file "$ch_sqfs" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *"can't stat mount point: /var/tmp/file"* ]]

    # input is file but not sqfs
    run ch-run Build.missing -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"unknown image type: Build.missing"* ]]

    # input has same magic number but is broken
    sq_tmp="${CH_TEST_TARDIR}"/tmp.sqfs
    # copy over magic number from sqfs to broken sqfs
    dd if="$ch_sqfs" of="$sq_tmp" conv=notrunc bs=1 count=4
    run ch-run -vvv "$sq_tmp" -- /bin/true
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *"actual: 6873 7173"* ]]
    [[ $output = *"can't open SquashFS: ${sq_tmp}"* ]]
    rm "${sq_tmp}"
}
