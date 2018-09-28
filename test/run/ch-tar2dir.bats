load ../common

@test 'ch-tar2dir: unpack image' {
    scope standard
    if ( image_ok "$ch_timg" ); then
        # image exists, remove so we can test new unpack
        rm -Rf --one-file-system "$ch_timg"
    fi
    ch-tar2dir "$ch_ttar" "$ch_imgdir"  # new unpack
    image_ok "$ch_timg"
    ch-tar2dir "$ch_ttar" "$ch_imgdir"  # overwrite
    image_ok "$ch_timg"
}

@test 'ch-tar2dir: /dev cleaning' {  # issue #157
    scope standard
    [[ ! -e $ch_timg/dev/foo ]]
    [[ -e $ch_timg/mnt/dev/foo ]]
    ch-run "$ch_timg" -- test -e /mnt/dev/foo
}

@test 'ch-tar2dir: errors' {
    scope quick
    # tarball doesn't exist
    run ch-tar2dir does_not_exist.tar.gz "$ch_imgdir"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't read does_not_exist.tar.gz"* ]]

    # tarball exists but isn't readable
    touch "${BATS_TMPDIR}/unreadable.tar.gz"
    chmod 000 "${BATS_TMPDIR}/unreadable.tar.gz"
    run ch-tar2dir "${BATS_TMPDIR}/unreadable.tar.gz" "$ch_imgdir"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't read ${BATS_TMPDIR}/unreadable.tar.gz"* ]]
}

