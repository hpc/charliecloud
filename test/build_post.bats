load common

@test 'nothing unexpected in tarball directory' {
    scope quick
    # We want nothing that's not a .tar.gz or .pg_missing.
    run find "$TARDIR" -mindepth 1 \
        -not \( -name '*.tar.gz' -o -name '*.pq_missing' \)
    echo "$output"
    [[ $output = '' ]]
}
