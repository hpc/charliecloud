load ../common

fromhost_clean () {
    [[ $1 ]]
    for file in {mnt,usr/bin}/sotest \
                {lib,mnt,usr/lib,usr/local/lib}/libsotest.so.1{.0,} \
                /usr/local/cuda-9.1/targets/x86_64-linux/lib/libsotest.so.1{.0,} \
                /mnt/sotest.c \
                /etc/ld.so.cache ; do
        rm -f "$1/$file"
    done
    fromhost_clean_p "$1"
}

fromhost_clean_p () {
    run fromhost_ls "$1"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ -z $output ]]
}

fromhost_ls () {
    find "$1" -xdev \( -name '*sotest*' -o -name 'ld.so.cache' \) -ls
}

@test 'ch-fromhost (Debian)' {
    scope standard
    prerequisites_ok debian9
    IMG=$IMGDIR/debian9

    # --cmd
    fromhost_clean "$IMG"
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' "$IMG"
    fromhost_ls "$IMG"
    test -f "$IMG/usr/bin/sotest"
    test -f "$IMG/usr/local/lib/libsotest.so.1.0"
    test -L "$IMG/usr/local/lib/libsotest.so.1"
    ch-run "$IMG" -- /sbin/ldconfig -p | grep -F sotest
    ch-run "$IMG" -- sotest
    rm "$IMG/usr/bin/sotest"
    rm "$IMG/usr/local/lib/libsotest.so.1.0"
    rm "$IMG/usr/local/lib/libsotest.so.1"
    rm "$IMG/etc/ld.so.cache"
    fromhost_clean_p "$IMG"

    # --cmd twice
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' \
                   --cmd 'cat sotest/files_inferrable.txt' "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"

    # --file
    ch-fromhost -v --file sotest/files_inferrable.txt "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"

    # --file twice
    ch-fromhost -v --file sotest/files_inferrable.txt \
                   --file sotest/files_inferrable.txt "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"

    # --cmd and --file
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' \
                   --file sotest/files_inferrable.txt "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"

    # --dest
    ch-fromhost -v --file sotest/files_inferrable.txt \
                   --file sotest/files_noninferrable.txt \
                   --dest /mnt "$IMG"
    ch-run "$IMG" -- sotest
    ch-run "$IMG" -- test -f /mnt/sotest.c
    fromhost_clean "$IMG"

    # file that needs --dest but not specified
    run ch-fromhost -v --file sotest/files_noninferrable.txt "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no destination for: sotest/sotest.c'* ]]
    fromhost_clean_p "$IMG"

    # --no-infer
    ch-run -w "$IMG" -- /sbin/ldconfig  # restore default cache
    ch-fromhost -v --cmd 'echo sotest/bin/sotest' \
                   --no-infer --dest /usr/bin "$IMG"
    ch-fromhost -v --cmd 'echo sotest/lib/libsotest.so.1.0' \
                   --no-infer --dest /usr/local/lib "$IMG"
    fromhost_ls "$IMG"
    ch-run "$IMG" -- /sbin/ldconfig -p | grep -F sotest || true
    run ch-run "$IMG" -- sotest
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'libsotest.so.1: cannot open shared object file'* ]]
    fromhost_clean "$IMG"

    # no --verbose
    ch-fromhost --file sotest/files_inferrable.txt "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"

    # --cmd no argument
    run ch-fromhost "$IMG" --cmd
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--cmd must not be empty'* ]]
    fromhost_clean_p "$IMG"
    # --cmd empty
    run ch-fromhost --cmd true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$IMG"
    # --cmd fails
    run ch-fromhost --cmd false
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'command failed: false'* ]]
    fromhost_clean_p "$IMG"

    # --file no argument
    run ch-fromhost "$IMG" --file
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--file must not be empty'* ]]
    fromhost_clean_p "$IMG"
    # --file empty
    run ch-fromhost --file /dev/null "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$IMG"
    # --file does not exist
    run ch-fromhost --file /doesnotexist "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'/doesnotexist: No such file or directory'* ]]
    [[ $output = *'cannot read file: /doesnotexist'* ]]
    fromhost_clean_p "$IMG"

    # neither --cmd nor --file
    run ch-fromhost "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$IMG"

    # --dest no argument
    run ch-fromhost "$IMG" --dest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--dest must not be empty'* ]]
    fromhost_clean_p "$IMG"
    # --dest not an absolute path
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest relative "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not an absolute path: relative'* ]]
    fromhost_clean_p "$IMG"
    # --dest does not exist
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest /doesnotexist "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not a directory:'* ]]
    fromhost_clean_p "$IMG"
    # --dest is not a directory
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest /bin/sh "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not a directory:'* ]]
    fromhost_clean_p "$IMG"

    # image does not exist
    run ch-fromhost --file sotest/files_inferrable.txt /doesnotexist
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'image not a directory: /doesnotexist'* ]]
    fromhost_clean_p "$IMG"
    # image specified twice
    run ch-fromhost --file sotest/files_inferrable.txt "$IMG" "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'duplicate image path'* ]]
    fromhost_clean_p "$IMG"
}

@test 'ch-fromhost (CentOS)' {
    scope full
    prerequisites_ok centos7
    IMG=$IMGDIR/centos7

    fromhost_clean "$IMG"
    ch-fromhost -v --file sotest/files_inferrable.txt "$IMG"
    fromhost_ls "$IMG"
    test -f "$IMG/usr/bin/sotest"
    test -f "$IMG/lib/libsotest.so.1.0"
    test -L "$IMG/lib/libsotest.so.1"
    ch-run "$IMG" -- /sbin/ldconfig -p | grep -F sotest
    ch-run "$IMG" -- sotest
    rm "$IMG/usr/bin/sotest"
    rm "$IMG/lib/libsotest.so.1.0"
    rm "$IMG/lib/libsotest.so.1"
    rm "$IMG/etc/ld.so.cache"
    fromhost_clean_p "$IMG"
}

@test 'ch-fromhost --nvidia with GPU' {
    scope full
    prerequisites_ok nvidia
    command -v nvidia-container-cli >/dev/null 2>&1 \
        || skip 'nvidia-container-cli not in PATH'
    IMG=$IMGDIR/nvidia

    # nvidia-container-cli --version (to make sure it's linked correctly)
    nvidia-container-cli --version

    # Skip if nvidia-container-cli can't find CUDA.
    run nvidia-container-cli list --binaries --libraries
    echo "$output"
    if [[ $status -eq 1 ]]; then
        if [[ $output = *'cuda error'* ]]; then
            skip "nvidia-container-cli can't find CUDA"
        fi
        false
    fi

    # --nvidia
    ch-fromhost -v --nvidia "$IMG"

    # nvidia-smi runs in guest
    ch-run "$IMG" -- nvidia-smi -L

    # nvidia-smi -L matches host
    host=$(nvidia-smi -L)
    echo "host GPUs:"
    echo "$host"
    guest=$(ch-run "$IMG" -- nvidia-smi -L)
    echo "guest GPUs:"
    echo "$guest"
    cmp <(echo "$host") <(echo "$guest")

    # --nvidia and --cmd
    fromhost_clean "$IMG"
    ch-fromhost --nvidia --file sotest/files_inferrable.txt "$IMG"
    ch-run "$IMG" -- nvidia-smi -L
    ch-run "$IMG" -- sotest
    # --nvidia and --file
    fromhost_clean "$IMG"
    ch-fromhost --nvidia --cmd 'cat sotest/files_inferrable.txt' "$IMG"
    ch-run "$IMG" -- nvidia-smi -L
    ch-run "$IMG" -- sotest

    # CUDA sample
    SAMPLE=/matrixMulCUBLAS
    # should fail without ch-fromhost --nvidia
    fromhost_clean "$IMG"
    run ch-run "$IMG" -- $SAMPLE
    echo "$output"
    [[ $status -eq 127 ]]
    [[ $output =~ 'matrixMulCUBLAS: error while loading shared libraries' ]]
    # should succeed with it
    fromhost_clean_p "$IMG"
    ch-fromhost --nvidia "$IMG"
    run ch-run "$IMG" -- $SAMPLE
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output =~ 'Comparing CUBLAS Matrix Multiply with CPU results: PASS' ]]
}

@test 'ch-fromhost --nvidia without GPU' {
    scope full
    prerequisites_ok nvidia
    IMG=$IMGDIR/nvidia

    # --nvidia should give a proper error whether or not nvidia-container-cli
    # is available.
    if ( command -v nvidia-container-cli >/dev/null 2>&1 ); then
        # nvidia-container-cli in $PATH
        run nvidia-container-cli list --binaries --libraries
        echo "$output"
        if [[ $status -eq 0 ]]; then
            # found CUDA; skip
            skip 'nvidia-container-cli found CUDA'
        else
            [[ $status -eq 1 ]]
            [[ $output = *'cuda error'* ]]
            run ch-fromhost -v --nvidia "$IMG"
            echo "$output"
            [[ $status -eq 1 ]]
            [[ $output = *'does this host have GPUs'* ]]
        fi
    else
        # nvidia-container-cli not in $PATH
        run ch-fromhost -v --nvidia "$IMG"
        echo "$output"
        [[ $status -eq 1 ]]
        r="nvidia-container-cli: (command )?not found"
        [[ $output =~ $r ]]
        [[ $output =~ 'nvidia-container-cli failed' ]]
    fi
}

