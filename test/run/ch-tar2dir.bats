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
    # Did we raise hidden files correctly?
    [[ -e $ch_timg/.hiddenfile1 ]]
    [[ -e $ch_timg/..hiddenfile2 ]]
    [[ -e $ch_timg/...hiddenfile3 ]]
}

@test 'ch-tar2dir: /dev cleaning' {  # issue #157
    scope standard
    # Are all fixtures present in tarball?
    present=$(tar tf "$ch_ttar" | grep -F deleteme)
    [[ $(echo "$present" | wc -l) -eq 4 ]]
    echo "$present" | grep -E '^img/dev/deleteme$'
    echo "$present" | grep -E '^./dev/deleteme$'
    echo "$present" | grep -E '^dev/deleteme$'
    echo "$present" | grep -E '^img/mnt/dev/dontdeleteme$'
    # Did we remove the right fixtures?
    [[ -e $ch_timg/mnt/dev/dontdeleteme ]]
    [[ $(ls -Aq "${ch_timg}/dev") -eq 0 ]]
    ch-run "$ch_timg" -- test -e /mnt/dev/dontdeleteme
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

