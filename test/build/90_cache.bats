load ../common

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
}

# Use new file so we can test cache delettion without disturbing the the rest
# of the ch-image tests in 50_ch-image.bats

@test 'ch-image build-cache' {
    # TODO
    run ch-image build-cache
    run ch-image build-cache --gc
    run ch-image build-cache --tree-text
    run ch-image build-cache --tree-dot
    run ch-image build-cache --reset
    # FIXME
    false
}
