load common

@test 'nothing unexpected in tarball directory' {
    # We want nothing that's not a .tar.gz or .pg_missing...
    run find $TARDIR -mindepth 1 \
        -not \( -name '*.tar.gz' -o -name '*.pq_missing' \)
    echo "$output"
    [[ $output = '' ]]
    # ... and nothing we didn't just create.
    run find $TARDIR -mindepth 1 -mmin +120
    echo "$output"
    [[ $output = '' ]]
}
