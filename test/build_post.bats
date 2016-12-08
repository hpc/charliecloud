load common

@test 'nothing unexpected in tarball directory' {
    # we want nothing that's not a .tar.gz, and nothing we didn't just create
    run find $TARDIR -mindepth 1 -not -name '*.tar.gz'
    echo "$output"
    [[ $output = '' ]]
    run find $TARDIR -mindepth 1 -mmin +120
    echo "$output"
    [[ $output = '' ]]
}
