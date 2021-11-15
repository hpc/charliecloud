load common

@test 'prepare images directory' {
    scope quick
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
        echo "$d"
        test -d "${d}"
        test -d "${d}/pass"
        test -f "${d}/pass/file"
        test -d "${d}/nopass"
        test -d "${d}/nopass/dir"
        test -f "${d}/nopass/file"
    done
}

@test 'ch-checkns' {
    scope quick
    "${ch_bin}/ch-checkns"
}
