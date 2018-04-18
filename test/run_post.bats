load common

fromhost_clean () {
    for file in {mnt,usr/bin}/sotest \
                {mnt,usr/lib}/libsotest.so.1{.0,} \
                /mnt/sotest.c \
                /etc/ld.so.cache ; do
        rm -f $1/$file
    done
    fromhost_clean_p $1
}

fromhost_clean_p () {
    run fromhost_ls $1
    echo "$output"
    [[ $status -eq 0 ]]
    [[ -z $output ]]
}

fromhost_ls () {
    find $1 -xdev \( -name '*sotest*' -o -name 'ld.so.cache' \) -ls
}

@test 'ch-fromhost' {
    scope standard
    prerequisites_ok fromhost
    IMG=$IMGDIR/fromhost

    # --cmd
    fromhost_clean $IMG
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' $IMG
    fromhost_ls $IMG
    test -f $IMG/usr/bin/sotest
    test -f $IMG/usr/lib/libsotest.so.1.0
    test -L $IMG/usr/lib/libsotest.so.1
    ch-run $IMG -- /sbin/ldconfig -p | fgrep sotest
    ch-run $IMG -- sotest
    rm $IMG/usr/bin/sotest
    rm $IMG/usr/lib/libsotest.so.1.0
    rm $IMG/usr/lib/libsotest.so.1
    rm $IMG/etc/ld.so.cache
    fromhost_clean_p $IMG

    # --cmd twice
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' \
                   --cmd 'cat sotest/files_inferrable.txt' $IMG
    ch-run $IMG -- sotest
    fromhost_clean $IMG

    # --file
    ch-fromhost -v --file sotest/files_inferrable.txt $IMG
    ch-run $IMG -- sotest
    fromhost_clean $IMG

    # --file twice
    ch-fromhost -v --file sotest/files_inferrable.txt \
                   --file sotest/files_inferrable.txt $IMG
    ch-run $IMG -- sotest
    fromhost_clean $IMG

    # --cmd and --file
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' \
                   --file sotest/files_inferrable.txt $IMG
    ch-run $IMG -- sotest
    fromhost_clean $IMG

    # --dest
    ch-fromhost -v --file sotest/files_inferrable.txt \
                   --file sotest/files_noninferrable.txt \
                   --dest /mnt $IMG
    ch-run $IMG -- sotest
    ch-run $IMG -- test -f /mnt/sotest.c
    fromhost_clean $IMG

    # file that needs --dest but not specified
    run ch-fromhost -v --file sotest/files_noninferrable.txt $IMG
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'no destination for: sotest/sotest.c' ]]
    fromhost_clean_p $IMG

    # --no-infer
    ch-run -w $IMG -- /sbin/ldconfig  # restore default cache
    ch-fromhost -v --cmd 'echo sotest/bin/sotest' \
                   --no-infer --dest /usr/bin $IMG
    ch-fromhost -v --cmd 'echo sotest/lib/libsotest.so.1.0' \
                   --no-infer --dest /usr/lib $IMG
    fromhost_ls $IMG
    ch-run $IMG -- /sbin/ldconfig -p | fgrep sotest || true
    run ch-run $IMG -- sotest
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output =~ 'libsotest.so.1: cannot open shared object file' ]]
    fromhost_clean $IMG

    # no --verbose
    ch-fromhost --file sotest/files_inferrable.txt $IMG
    ch-run $IMG -- sotest
    fromhost_clean $IMG

    # --cmd no argument
    run ch-fromhost $IMG --cmd
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--cmd must not be empty' ]]
    fromhost_clean_p $IMG
    # --cmd empty
    run ch-fromhost --cmd true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'empty file list' ]]
    fromhost_clean_p $IMG
    # --cmd fails
    run ch-fromhost --cmd false
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'command failed: false' ]]
    fromhost_clean_p $IMG

    # --file no argument
    run ch-fromhost $IMG --file
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--file must not be empty' ]]
    fromhost_clean_p $IMG
    # --file empty
    run ch-fromhost --file /dev/null $IMG
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'empty file list' ]]
    fromhost_clean_p $IMG
    # --file does not exist
    run ch-fromhost --file /doesnotexist $IMG
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '/doesnotexist: No such file or directory' ]]
    [[ $output =~ 'cannot read file: /doesnotexist' ]]
    fromhost_clean_p $IMG

    # neither --cmd nor --file
    run ch-fromhost $IMG
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'empty file list' ]]
    fromhost_clean_p $IMG

    # --dest no argument
    run ch-fromhost $IMG --dest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ '--dest must not be empty' ]]
    fromhost_clean_p $IMG
    # --dest not an absolute path
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest relative $IMG
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'not an absolute path: relative' ]]
    fromhost_clean_p $IMG
    # --dest does not exist
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest /doesnotexist $IMG
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'not a directory:' ]]
    fromhost_clean_p $IMG
    # --dest is not a directory
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest /bin/sh $IMG
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'not a directory:' ]]
    fromhost_clean_p $IMG

    # image does not exist
    run ch-fromhost --file sotest/files_inferrable.txt /doesnotexist
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'image not a directory: /doesnotexist' ]]
    fromhost_clean_p $IMG
    # image specified twice
    run ch-fromhost --file sotest/files_inferrable.txt $IMG $IMG
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output =~ 'duplicate image path' ]]
    fromhost_clean_p $IMG
}

@test 'ch-fromhost --nvidia' {
    scope standard
    prerequisites_ok fromhost
    skip 'not implemented'
    # --nvidia
    # --nvidia and --cmd
    # --nvidia and --file
}

