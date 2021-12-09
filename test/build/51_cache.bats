load ../common

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
}

# Use new file so we can test cache delettion without disturbing the the rest
# of the ch-image tests in 50_ch-image.bats

@test 'ch-image build-cache' {
    # FIXME
    run ch-image build-cache
    [[ $status -eq 0 ]]
    run ch-image build-cache --gc
    [[ $status -eq 0 ]]
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    run ch-image build-cache --tree-dot
    [[ $status -eq 0 ]]
    run ch-image build-cache --reset
    [[ $status -eq 0 ]]
}

@test 'ch-image (cache modes)'{
    # FIXME: make sure github workflow has correct git
    run ch-image -vv list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'build cache: enable (default)'* ]]
    [[ $output = *'download cache: enable (default)'* ]]

    run ch-image --no-cache -vv list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'build cache: rebuild (command line)'* ]]
    [[ $output = *'download cache: write-only (command line)'* ]]

    # bu rebuild, dl default
    run ch-image --build-cache=rebuild -vv list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'build cache: rebuild (command line)'* ]]

    # bu enable, dl default
    run ch-image --build-cache=enable -vv list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'build cache: enable (command line)'* ]]

    # bu disable, dl default
    run ch-image --build-cache=disable -vv list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'build cache: disable (command line)'* ]]

    # dl write-only, bu default
    run ch-image --download-cache=write-only -vv list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'build cache:'*'(default'* ]]
    [[ $output = *'download cache: write-only (command line)'* ]]

    # dl enable, bu default
    run ch-image --download-cache=enable -vv list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'download cache: enable (command line)'* ]]
}
