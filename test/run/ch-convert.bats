load ../common

@test 'ch-convert: format inference' {
    scope standard

    # Test input only; output uses same code. Test cases match all the
    # criteria to validate the priority. We don't exercise every possible
    # descriptor pattern, only those I thought had potential for error.

    # SquashFS
    run ch-convert -n ./foo:bar.sqfs out.tar
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   squash'* ]]

    # tar
    run ch-convert -n ./foo:bar.tar out.tar
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   tar'* ]]
    run ch-convert -n ./foo:bar.tgz out.tar
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   tar'* ]]
    run ch-convert -n ./foo:bar.tar.Z out.tar
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   tar'* ]]
    run ch-convert -n ./foo:bar.tar.gz out.tar
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   tar'* ]]

    # directory
    run ch-convert -n ./foo:bar out.tar
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   dir'* ]]

    # builders
    run ch-convert -n foo:bar out.tar
    echo "$output"
    if command -v ch-image > /dev/null 2>&1; then
        [[ $status -eq 0 ]]
        [[ $output = *'input:   ch-image'* ]]
    elif command -v docker > /dev/null 2>&1; then
        [[ $status -eq 0 ]]
        [[ $output = *'input:   docker'* ]]
    else
        [[ $status -eq 1 ]]
        [[ $output = *'no builder found' ]]
    fi

    # no inference
    run ch-convert -n foo out.tar
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't infer from: foo"* ]]
}

@test 'ch-convert: filename inference' {
    scope standard

    echo
    # ch-image -> dir
    run ch-convert -n -i ch-image -o dir foo/bar "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  dir       ${BATS_TMPDIR}/foo%bar"* ]]
    # docker -> dir
    run ch-convert -n -i docker -o dir foo/bar "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  dir       ${BATS_TMPDIR}/foo%bar"* ]]
    # squash -> dir
    run ch-convert -n -i squash -o dir foo.sqfs "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  dir       ${BATS_TMPDIR}/foo"* ]]
    # tar -> dir
    run ch-convert -n -i tar -o dir foo.tar.gz "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  dir       ${BATS_TMPDIR}/foo"* ]]

    echo
    # ch-image -> squash
    run ch-convert -n -i ch-image -o squash foo/bar "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  squash    ${BATS_TMPDIR}/foo%bar.sqfs"* ]]
    # dir -> squash
    run ch-convert -n -i dir -o squash foo "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  squash    ${BATS_TMPDIR}/foo.sqfs"* ]]
    # docker -> squash
    run ch-convert -n -i docker -o squash foo/bar "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  squash    ${BATS_TMPDIR}/foo%bar.sqfs"* ]]
    # tar -> squash
    run ch-convert -n -i tar -o squash foo.tar.gz "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  squash    ${BATS_TMPDIR}/foo.sqfs"* ]]

    echo
    # ch-image -> tar
    run ch-convert -n -i ch-image -o tar foo/bar "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  tar       ${BATS_TMPDIR}/foo%bar.tar.gz"* ]]
    # dir -> tar
    run ch-convert -n -i dir -o tar foo "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  tar       ${BATS_TMPDIR}/foo.tar.gz"* ]]
    # docker -> tar
    run ch-convert -n -i docker -o tar foo/bar "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  tar       ${BATS_TMPDIR}/foo%bar.tar.gz"* ]]
    # squash -> tar
    run ch-convert -n -i squash -o tar foo.sqfs "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  tar       ${BATS_TMPDIR}/foo.tar.gz"* ]]

    echo
    # squash no extension -> tar
    run ch-convert -n -i squash -o tar foo "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  tar       ${BATS_TMPDIR}/foo.tar.gz"* ]]
    # tar no extension -> squash
    run ch-convert -n -i tar -o squash foo "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"output:  squash    ${BATS_TMPDIR}/foo.sqfs"* ]]
}

@test 'ch-convert: errors' {
    scope standard

    # same format
    run ch-convert -n foo.tar foo.tar.gz
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: input and output formats must be different'* ]]

    # output directory not an image
    run ch-convert -n foo.sqfs "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'FIXME'* ]]
}

@test 'ch-convert: all formats' {
    scope standard

    # FIXME: pedantic mode

    # The most efficient way to do this test would be to start with a
    # directory, cycle through all the formats one at a time, with directory
    # being last, then compare the starting and ending directories. That
    # corresponds to visiting all the cells in this matrix, starting from one
    # labeled "a", ending in one labeled "b", and skipping those labeled with
    # a dash. Also, if visit n is in column i, then the next visit n+1 must be
    # in row i. This approach does each conversion exactly once.
    #
    #               output ->
    #               | dir      | ch-image | docker   | squash   | tar     |
    # input         +----------+----------+----------+----------+---------+
    #   |  dir      |    —     |    a     |    a     |    a     |    a    |
    #   v  ch-image |    b     |    —     |          |          |         |
    #      docker   |    b     |          |    —     |          |         |
    #      squash   |    b     |          |          |    —     |         |
    #      tar      |    b     |          |          |          |    —    |
    #               +----------+----------+----------+----------+---------+
    #
    # Because we start with a directory already available, this would yield
    # 5*5 - 5 - 1 = 19 conversions. However, I was not able to figure out a
    # traversal order that would meet the constraints.
    #
    # Thus, we use the following algorithm with some caching. I think it is
    # close but I haven't counted.
    #
    #   for every format i except dir:             (4 iterations)
    #     convert start_dir -> i
    #     convert i -> finish_dir
    #     compare start_dir with finish_dir
    #     for every format j except i and dir:     (3)
    #          convert i -> j
    #          convert j -> finish_dir
    #          compare start_dir with finish_dir
    #
    # This yields 4 * (2 + 3 * 2) = 32 conversions, due I think to excess
    # conversions to dir. However, it can better isolate where the conversion
    # went wrong, because the chain is 3 conversions long rather than 19.

    rm -Rf --one-file-system "${BATS_TMPDIR}/convert.*"
    ct=0
    for i in ch-image docker squash tar; do
        ct=$((ct+1))
        echo
        echo "outer ${ct}: dir -> ${i}"
        for j in ch-image docker squash tar; do
            if [[ $i != $j ]]; then
                ct=$((ct+1))
                echo "inner $ct: $i -> $j"
            fi
            ct=$((ct+1))
            echo "inner $ct: $j -> dir"
            # compare here
        done
    done

    false
}
