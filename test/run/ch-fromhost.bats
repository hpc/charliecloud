load ../common

setup () {
    [[ $CH_TEST_PACK_FMT = *-unpack ]] || skip 'need writeable image'
    [[ $ch_libc = glibc ]] || skip 'glibc only'
}

fromhost_clean () {
    [[ $1 ]]
    # We used to delete only specific paths, but this turned into an unwieldy
    # mess of wildcards that obscured the original specificity purpose.
    rm -f "${1}/ld.so.cache"
    find "$1" -xdev \(           \
         -name 'libcuda*'        \
      -o -name 'libnvidia*'      \
      -o -name 'libfabric'       \
      -o -name libsotest-fi.so   \
      -o -name libsotest.so.1    \
      -o -name libsotest.so.1.0  \
      -o -name sotest            \
      -o -name sotest.c          \
    \) -print -delete
    ch-run -w "$1" -- /sbin/ldconfig  # restore default cache
    fromhost_clean_p "$1"
}

fromhost_clean_p () {
    ch-run "$1" -- /sbin/ldconfig -p | grep -F libsotest && return 1
    run fromhost_ls "$1"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ -z $output ]]
}

fromhost_ls () {
    find "$1" -xdev -name '*sotest*' -ls
}

@test 'ch-fromhost (CentOS)' {
    scope standard
    prerequisites_ok almalinux_8ch
    img=${ch_imgdir}/almalinux_8ch

    libpath=$(ch-fromhost --lib-path "$img")
    echo "libpath: ${libpath}"

    # --file
    fromhost_clean "$img"
    ch-fromhost -v --file sotest/files_inferrable.txt "$img"
    fromhost_ls "$img"
    test -f "${img}/usr/bin/sotest"
    test -f "${img}${libpath}/libsotest.so.1.0"
    test -L "${img}${libpath}/libsotest.so.1"
    ch-run "$img" -- /sbin/ldconfig -p | grep -F libsotest
    ch-run "$img" -- sotest
    rm "${img}/usr/bin/sotest"
    rm "${img}${libpath}/libsotest.so.1.0"
    rm "${img}${libpath}/libsotest.so.1"
    ch-run -w "$img" -- /sbin/ldconfig
    fromhost_clean_p "$img"

    # --cmd
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' "$img"
    ch-run "$img" -- sotest

    # --path
    ch-fromhost -v --path sotest/bin/sotest \
                   --path sotest/lib/libsotest.so.1.0 \
                   "$img"
    ch-run "$img" -- sotest
    fromhost_clean "$img"

    # --cmd and --file
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' \
                   --file sotest/files_inferrable.txt "$img"
    ch-run "$img" -- sotest
    fromhost_clean "$img"

    # --dest
    ch-fromhost -v --file sotest/files_inferrable.txt \
                   --dest /mnt "$img" \
                   --path sotest/sotest.c
    ch-run "$img" -- sotest
    ch-run "$img" -- test -f /mnt/sotest.c
    fromhost_clean "$img"

    # --dest overrides inference, but ldconfig still run
    ch-fromhost -v --dest /lib \
                   --file sotest/files_inferrable.txt \
                   "$img"
    ch-run "$img" -- /lib/sotest
    fromhost_clean "$img"

    # --no-ldconfig
    ch-fromhost -v --no-ldconfig --file sotest/files_inferrable.txt "$img"
      test -f "${img}/usr/bin/sotest"
      test -f "${img}${libpath}/libsotest.so.1.0"
    ! test -L "${img}${libpath}/libsotest.so.1"
    ! ( ch-run "$img" -- /sbin/ldconfig -p | grep -F libsotest )
    run ch-run "$img" -- sotest
    echo "$output"
    [[ $status -eq 127 ]]
    [[ $output = *'libsotest.so.1: cannot open shared object file'* ]]
    fromhost_clean "$img"

    # no --verbose
    ch-fromhost --file sotest/files_inferrable.txt "$img"
    ch-run "$img" -- sotest
    fromhost_clean "$img"

    # destination directory not writeable (#323)
    chmod -v u-w "${img}/mnt"
    ch-fromhost --dest /mnt --path sotest/sotest.c "$img"
    test -w "${img}/mnt"
    test -f "${img}/mnt/sotest.c"
    fromhost_clean "$img"
}

@test 'ch-fromhost (Debian)' {
    scope full
    prerequisites_ok debian_9ch
    img=${ch_imgdir}/debian_9ch

    libpath=$(ch-fromhost --lib-path "$img")
    echo "libpath: ${libpath}"

    fromhost_clean "$img"
    ch-fromhost -v --file sotest/files_inferrable.txt "$img"
    fromhost_ls "$img"
    test -f "${img}/usr/bin/sotest"
    test -f "${img}/${libpath}/libsotest.so.1.0"
    test -L "${img}/${libpath}/libsotest.so.1"
    ch-run "$img" -- /sbin/ldconfig -p | grep -F libsotest
    ch-run "$img" -- sotest
    rm "${img}/usr/bin/sotest"
    rm "${img}/${libpath}/libsotest.so.1.0"
    rm "${img}/${libpath}/libsotest.so.1"
    rm "${img}/etc/ld.so.cache"
    fromhost_clean_p "$img"
}

@test 'ch-fromhost errors' {
    scope standard
    prerequisites_ok almalinux_8ch
    img=${ch_imgdir}/almalinux_8ch

    # no image
    run ch-fromhost --path sotest/sotest.c
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no image specified'* ]]
    fromhost_clean_p "$img"

    # image is not a directory
    run ch-fromhost --path sotest/sotest.c /etc/motd
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'image not a directory: /etc/motd'* ]]
    fromhost_clean_p "$img"

    # two image arguments
    run ch-fromhost --path sotest/sotest.c "$img" foo
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'duplicate image: foo'* ]]
    fromhost_clean_p "$img"

    # no files argument
    run ch-fromhost "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$img"

    # file that needs --dest but not specified
    run ch-fromhost -v --path sotest/sotest.c "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no destination for: sotest/sotest.c'* ]]
    fromhost_clean_p "$img"

    # file with colon in name
    run ch-fromhost -v --path 'foo:bar' "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"paths can't contain colon: foo:bar"* ]]
    fromhost_clean_p "$img"
    # file with newlines in name
    run ch-fromhost -v --path $'foo\nbar' "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"no destination for: foo"* ]]
    fromhost_clean_p "$img"

    # --cmd no argument
    run ch-fromhost "$img" --cmd
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--cmd must not be empty'* ]]
    fromhost_clean_p "$img"
    # --cmd empty
    run ch-fromhost --cmd true "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$img"
    # --cmd fails
    run ch-fromhost --cmd false "$img"
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

    # --ofi no argument
    run ch-fromhost "$img" --ofi
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--ofi must not be empty'* ]]

    # --ofi path doesn't exist
    run ch-fromhost "$img" --ofi /rando/path
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'is not, or does not contain, valid OFI dso(s)'* ]]

    # --ofi path has no -fi.so
    run ch-fromhost "$img" --ofi "$CHTEST_DIR"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'is not, or does not contain, valid OFI dso(s)'* ]]

    # --ofi file is not a -fi.so
    run ch-fromhost "$img" --ofi "$CHTEST_DIR/sotest/libsotest.so"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'is not, or does not contain, valid OFI dso(s)'* ]]

    # --path no argument
    run ch-fromhost "$img" --path
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--path must not be empty'* ]]
    fromhost_clean_p "$img"
    # --path does not exist
    run ch-fromhost --dest /mnt --path /doesnotexist "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'No such file or directory'* ]]
    [[ $output = *'cannot inject: /doesnotexist'* ]]
    fromhost_clean_p "$img"

    # --dest no argument
    run ch-fromhost "$img" --dest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--dest must not be empty'* ]]
    fromhost_clean_p "$img"
    # --dest not an absolute path
    run ch-fromhost --dest relative --path sotest/sotest.c "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not an absolute path: relative'* ]]
    fromhost_clean_p "$img"
    # --dest does not exist
    run ch-fromhost --dest /doesnotexist --path sotest/sotest.c "$img"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not a directory:'* ]]
    fromhost_clean_p "$img"
    # --dest is not a directory
    run ch-fromhost --dest /bin/sh --file sotest/sotest.c "$img"
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
    [[ $output = *'duplicate image'* ]]
    fromhost_clean_p "$img"

    # ldconfig gives no shared library path (#324)
    #
    # (I don't think this is the best way to get ldconfig to fail, but I
    # couldn't come up with anything better. E.g., bad ld.so.conf or broken
    # .so's seem to produce only warnings.)
    mv "${img}/sbin/ldconfig" "${img}/sbin/ldconfig.foo"
    run ch-fromhost --lib-path "$img"
    mv "${img}/sbin/ldconfig.foo" "${img}/sbin/ldconfig"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty path from ldconfig'* ]]
    fromhost_clean_p "$img"
}

@test 'ch-fromhost --ofi (OpenMPI)' {
    scope full
    prerequisites_ok openmpi
    img=${ch_imgdir}/openmpi

    ofidest=$(ch-fromhost --ofi-dest "$img")
    echo "provider dest: ${ofidest}"

    # The libsotest-fi.so is a dummy provider intended to exercise ch-fromhost
    # script logic. Succeed if ch-fromhost finds the container libfabric.so and
    # injects the libfabric-fi.so dummy executable in the directory /libfabric
    # where libfabric.so is found.
    img=${ch_imgdir}/openmpi
    ofi=${CHTEST_DIR}/sotest/lib/libfabric/libsotest-fi.so
    run ch-fromhost --ofi "${ofi}" "$img"
    echo "$output"
    [[ $status -eq 0 ]]
    test -f "${img}/${ofidest}/libsotest-fi.so"
    fromhost_clean "$img"
}

@test 'ch-fromhost --host-ofi (OpenMPI)' {
    scope full
    prerequisites_ok openmpi
    img=${ch_imgdir}/openmpi

    ofidest=$(ch-fromhost --ofi-dest "$img")
    echo "provider dest: ${ofidest}"

    old_ofi="$CH_FROMHOST_OFI"
    new_ofi=${CHTEST_DIR}/sotest/lib/libfabric
    export CH_FROMHOST_OFI="$new_ofi"
    img=${ch_imgdir}/openmpi
    run ch-fromhost "$img" --host-ofi
    echo "$output"
    [[ $status -eq 0 ]]
    test -f "${img}/${ofidest}/libsotest-fi.so"
    fromhost_clean "$img"
    export CH_FROMHOST_OFI="$old_ofi"
}

@test 'ch-fromhost --host-ofi with no host ofi' {
    scope full
    old_ofi="$CH_FROMHOST_OFI"
    unset CH_FROMHOST_OFI
    run ch-fromhost --host-ofi "$ch_timg"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'CH_FROMHOST_OFI not set'* ]]
    export "CH_FROMHOST_OFI=${old_ofi}"
}

@test 'ch-fromhost --nvidia with GPU' {
    scope full
    prerequisites_ok nvidia
    command -v nvidia-container-cli >/dev/null 2>&1 \
        || skip 'nvidia-container-cli not in PATH'
    img=${ch_imgdir}/nvidia

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
    [[ $status -eq 1 ]]
    [[ $output = *'CUDA error at'* ]]
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
    img=${ch_imgdir}/nvidia

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

