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
    img=${ch_imdir}/debian9

    # --cmd
    fromhost_clean "$img"
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' "$img"
    fromhost_ls "$img"
    test -f "${img}/usr/bin/sotest"
    test -f "${img}/usr/local/lib/libsotest.so.1.0"
    test -L "${img}/usr/local/lib/libsotest.so.1"
    ch-run "$img" -- /sbin/ldconfig -p | grep -F sotest
    ch-run "$img" -- sotest
    rm "${img}/usr/bin/sotest"
    rm "${img}/usr/local/lib/libsotest.so.1.0"
    rm "${img}/usr/local/lib/libsotest.so.1"
    rm "${img}/etc/ld.so.cache"
    fromhost_clean_p "$img"

    # --cmd twice
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' \
                   --cmd 'cat sotest/files_inferrable.txt' "$img"
    ch-run "$img" -- sotest
    fromhost_clean "$img"

    # --file
    ch-fromhost -v --file sotest/files_inferrable.txt "$img"
    ch-run "$img" -- sotest
    fromhost_clean "$img"

    # --file twice
    ch-fromhost -v --file sotest/files_inferrable.txt \
                   --file sotest/files_inferrable.txt "$img"
    ch-run "$img" -- sotest
    fromhost_clean "$img"

    # --cmd and --file
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' \
                   --file sotest/files_inferrable.txt "$img"
    ch-run "$img" -- sotest
    fromhost_clean "$img"

    # --dest
    ch-fromhost -v --file sotest/files_inferrable.txt \
                   --file sotest/files_noninferrable.txt \
                   --dest /mnt "$img"
    ch-run "$img" -- sotest
    ch-run "$img" -- test -f /mnt/sotest.c
    fromhost_clean "$img"

    # file that needs --dest but not specified
    run ch-fromhost -v --file sotest/files_noninferrable.txt "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no destination for: sotest/sotest.c'* ]]
    fromhost_clean_p "$img"

    # --no-infer
    ch-run -w "$img" -- /sbin/ldconfig  # restore default cache
    ch-fromhost -v --cmd 'echo sotest/bin/sotest' \
                   --no-infer --dest /usr/bin "$img"
    ch-fromhost -v --cmd 'echo sotest/lib/libsotest.so.1.0' \
                   --no-infer --dest /usr/local/lib "$img"
    fromhost_ls "$img"
    ch-run "$img" -- /sbin/ldconfig -p | grep -F sotest || true
    run ch-run "$img" -- sotest
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'libsotest.so.1: cannot open shared object file'* ]]
    fromhost_clean "$img"

    # no --verbose
    ch-fromhost --file sotest/files_inferrable.txt "$img"
    ch-run "$img" -- sotest
    fromhost_clean "$img"

    # --cmd no argument
    run ch-fromhost "$img" --cmd
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--cmd must not be empty'* ]]
    fromhost_clean_p "$img"
    # --cmd empty
    run ch-fromhost --cmd true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$img"
    # --cmd fails
    run ch-fromhost --cmd false
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'command failed: false'* ]]
    fromhost_clean_p "$img"

    # --file no argument
    run ch-fromhost "$img" --file
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--file must not be empty'* ]]
    fromhost_clean_p "$img"
    # --file empty
    run ch-fromhost --file /dev/null "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$img"
    # --file does not exist
    run ch-fromhost --file /doesnotexist "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'/doesnotexist: No such file or directory'* ]]
    [[ $output = *'cannot read file: /doesnotexist'* ]]
    fromhost_clean_p "$img"

    # neither --cmd nor --file
    run ch-fromhost "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$img"

    # --dest no argument
    run ch-fromhost "$img" --dest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--dest must not be empty'* ]]
    fromhost_clean_p "$img"
    # --dest not an absolute path
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest relative "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not an absolute path: relative'* ]]
    fromhost_clean_p "$img"
    # --dest does not exist
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest /doesnotexist "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not a directory:'* ]]
    fromhost_clean_p "$img"
    # --dest is not a directory
    run ch-fromhost --file sotest/files_noninferrable.txt \
                    --dest /bin/sh "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not a directory:'* ]]
    fromhost_clean_p "$img"

    # image does not exist
    run ch-fromhost --file sotest/files_inferrable.txt /doesnotexist
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'image not a directory: /doesnotexist'* ]]
    fromhost_clean_p "$img"
    # image specified twice
    run ch-fromhost --file sotest/files_inferrable.txt "$img" "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'duplicate image path'* ]]
    fromhost_clean_p "$img"
}

@test 'ch-fromhost (CentOS)' {
    scope full
    prerequisites_ok centos7
    img=${ch_imdir}/centos7

    fromhost_clean "$img"
    ch-fromhost -v --file sotest/files_inferrable.txt "$img"
    fromhost_ls "$img"
    test -f "${img}/usr/bin/sotest"
    test -f "${img}/lib/libsotest.so.1.0"
    test -L "${img}/lib/libsotest.so.1"
    ch-run "$img" -- /sbin/ldconfig -p | grep -F sotest
    ch-run "$img" -- sotest
    rm "${img}/usr/bin/sotest"
    rm "${img}/lib/libsotest.so.1.0"
    rm "${img}/lib/libsotest.so.1"
    rm "${img}/etc/ld.so.cache"
    fromhost_clean_p "$img"
}

@test 'ch-fromhost --nvidia with GPU' {
    scope full
    prerequisites_ok nvidia
    command -v nvidia-container-cli >/dev/null 2>&1 \
        || skip 'nvidia-container-cli not in PATH'
    img=${ch_imdir}/nvidia

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
    ch-fromhost -v --nvidia "$img"

    # nvidia-smi runs in guest
    ch-run "$img" -- nvidia-smi -L

    # nvidia-smi -L matches host
    host=$(nvidia-smi -L)
    echo "host GPUs:"
    echo "$host"
    guest=$(ch-run "$img" -- nvidia-smi -L)
    echo "guest GPUs:"
    echo "$guest"
    cmp <(echo "$host") <(echo "$guest")

    # --nvidia and --cmd
    fromhost_clean "$img"
    ch-fromhost --nvidia --file sotest/files_inferrable.txt "$img"
    ch-run "$img" -- nvidia-smi -L
    ch-run "$img" -- sotest
    # --nvidia and --file
    fromhost_clean "$img"
    ch-fromhost --nvidia --cmd 'cat sotest/files_inferrable.txt' "$img"
    ch-run "$img" -- nvidia-smi -L
    ch-run "$img" -- sotest

    # CUDA sample
    sample=/matrixMulCUBLAS
    # should fail without ch-fromhost --nvidia
    fromhost_clean "$img"
    run ch-run "$img" -- $sample
    echo "$output"
    [[ $status -eq 127 ]]
    [[ $output =~ 'matrixMulCUBLAS: error while loading shared libraries' ]]
    # should succeed with it
    fromhost_clean_p "$img"
    ch-fromhost --nvidia "$img"
    run ch-run "$img" -- $sample
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output =~ 'Comparing CUBLAS Matrix Multiply with CPU results: PASS' ]]
}

@test 'ch-fromhost --nvidia without GPU' {
    scope full
    prerequisites_ok nvidia
    img=${ch_imdir}/nvidia

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
            run ch-fromhost -v --nvidia "$img"
            echo "$output"
            [[ $status -eq 1 ]]
            [[ $output = *'does this host have GPUs'* ]]
        fi
    else
        # nvidia-container-cli not in $PATH
        run ch-fromhost -v --nvidia "$img"
        echo "$output"
        [[ $status -eq 1 ]]
        r="nvidia-container-cli: (command )?not found"
        [[ $output =~ $r ]]
        [[ $output =~ 'nvidia-container-cli failed' ]]
    fi
}

