load ../common

@test 'ch-run refuses to run if setgid' {
    scope quick
    CH_RUN_TMP=$BATS_TMPDIR/ch-run.setgid
    GID=$(id -g)
    GID2=$(id -G | cut -d' ' -f2)
    echo "GIDs: $GID $GID2"
    [[ $GID != $GID2 ]]
    cp -a $CH_RUN_FILE $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    chgrp $GID2 $CH_RUN_TMP
    chmod g+s $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    [[ -g $CH_RUN_TMP ]]
    run $CH_RUN_TMP --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ ': error (' ]]
    rm $CH_RUN_TMP
}

@test 'ch-run refuses to run if setuid' {
    scope quick
    [[ -n $CHTEST_HAVE_SUDO ]] || skip 'sudo not available'
    CH_RUN_TMP=$BATS_TMPDIR/ch-run.setuid
    cp -a $CH_RUN_FILE $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    sudo chown root $CH_RUN_TMP
    sudo chmod u+s $CH_RUN_TMP
    ls -l $CH_RUN_TMP
    [[ -u $CH_RUN_TMP ]]
    run $CH_RUN_TMP --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ ': error (' ]]
    sudo rm $CH_RUN_TMP
}

@test 'ch-run as root: --version and --test' {
    scope quick
    [[ -n $CHTEST_HAVE_SUDO ]] || skip 'sudo not available'
    sudo $CH_RUN_FILE --version
    sudo $CH_RUN_FILE --help
}

@test 'ch-run as root: run image' {
    scope standard
    # Running an image should work as root, but it doesn't, and I'm not sure
    # why, so skip this test. This fails in the test suite with:
    #
    #   ch-run: couldn't resolve image path: No such file or directory (ch-run.c:139:2)
    #
    # but when run manually (with same arguments?) it fails differently with:
    #
    #   $ sudo bin/ch-run $CH_TEST_IMGDIR/chtest -- true
    #   ch-run: [...]/chtest: Permission denied (ch-run.c:195:13)
    #
    skip 'issue #76'
    sudo $CH_RUN_FILE $CHTEST_IMG -- true
}

@test 'ch-run as root: root with non-zero GID refused' {
    scope quick
    [[ -n $CHTEST_HAVE_SUDO ]] || skip 'sudo not available'
    [[ -z $TRAVIS ]] || skip 'not permitted on Travis'
    run sudo -u root -g $(id -gn) $CH_RUN_FILE -v --version
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'error (' ]]
}
