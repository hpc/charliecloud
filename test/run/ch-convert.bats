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
