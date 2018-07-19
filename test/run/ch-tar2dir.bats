load ../common

@test 'ch-tar2dir: unpack image' {
    scope standard
    if ( image_ok "$CHTEST_IMG" ); then
        # image exists, remove so we can test new unpack
        rm -Rf --one-file-system "$CHTEST_IMG"
    fi
    ch-tar2dir "$CHTEST_TARBALL" "$IMGDIR"  # new unpack
    image_ok "$CHTEST_IMG"
    ch-tar2dir "$CHTEST_TARBALL" "$IMGDIR"  # overwrite
    image_ok "$CHTEST_IMG"
}

@test 'ch-tar2dir: /dev cleaning' {  # issue #157
    scope standard
    [[ ! -e $CHTEST_IMG/dev/foo ]]
    [[ -e $CHTEST_IMG/mnt/dev/foo ]]
    ch-run "$CHTEST_IMG" -- test -e /mnt/dev/foo
}

@test 'ch-tar2dir: errors' {
    scope quick
    # tarball doesn't exist
    run ch-tar2dir does_not_exist.tar.gz "$IMGDIR"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't read does_not_exist.tar.gz"* ]]

    # tarball exists but isn't readable
    touch "$BATS_TMPDIR/unreadable.tar.gz"
    chmod 000 "$BATS_TMPDIR/unreadable.tar.gz"
    run ch-tar2dir "$BATS_TMPDIR/unreadable.tar.gz" "$IMGDIR"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't read $BATS_TMPDIR/unreadable.tar.gz"* ]]
}

