load common

@test 'prepare images directory' {
    scope standard
    shopt -s nullglob  # globs that match nothing yield empty string
    if [[ -e $ch_imgdir ]]; then
        # Images directory exists. If all it contains is Charliecloud images
        # or supporting directories, or nothing, then we're ok. Remove any
        # images (this makes test-build and test-run follow the same path when
        # run on the same or different machines). Otherwise, error.
        for i in "$ch_imgdir"/*; do
            case $(basename "$i") in
                mounts|bind?)
                    continue
                    ;;
            esac
            if [[ -d $i && -f $i/WEIRD_AL_YANKOVIC ]]; then
                echo "found image ${i}; removing"
                rm -Rf --one-file-system "${i}"
            else
                echo "found non-image ${i}; aborting"
                false
            fi
        done
    fi
    mkdir -p "$ch_imgdir"
    mkdir -p "${ch_imgdir}/bind1"
    touch "${ch_imgdir}/bind1/file1"
    mkdir -p "${ch_imgdir}/bind2"
    touch "${ch_imgdir}/bind2/file2"
    mkdir -p "${ch_imgdir}/mounts"
}

@test 'permissions test directories exist' {
    scope standard
    [[ $CH_TEST_PERMDIRS = skip ]] && skip 'user request'
    for d in $CH_TEST_PERMDIRS; do
        d=${d}/perms_test
        echo "$d"
        test -d "${d}"
        test -d "${d}/pass"
        test -f "${d}/pass/file"
        test -d "${d}/nopass"
        test -d "${d}/nopass/dir"
        test -f "${d}/nopass/file"
    done
}

@test 'syscalls/pivot_root' {
    scope quick
    cd ../examples/syscalls
    ./pivot_root
}
