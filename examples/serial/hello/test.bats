load ../../../test/common

setup () {
    scope standard
    prerequisites_ok hello
}

@test "$EXAMPLE_TAG/hello" {
    run ch-run $EXAMPLE_IMG -- /hello/hello.sh
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = 'hello world' ]]
}

@test "$EXAMPLE_TAG/distribution sanity" {
    # Try various simple things that should work in a basic Debian
    # distribution. (This does not test anything Charliecloud manipulates.)
    ch-run $EXAMPLE_IMG -- /bin/bash -c true
    ch-run $EXAMPLE_IMG -- /bin/true
    ch-run $EXAMPLE_IMG -- find /etc -name 'a*'
    ch-run $EXAMPLE_IMG -- sh -c 'echo foo | /bin/egrep foo'
    ch-run $EXAMPLE_IMG -- nice true
}
