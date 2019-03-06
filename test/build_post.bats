load common

@test 'nothing unexpected in tarball directory' {
    scope quick
    run find "$ch_tardir" -mindepth 1 \
        -not \( -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.pq_missing' \)
    echo "$output"
    [[ $output = '' ]]
}
