load ../../test/common

setup () {
    IMG=$IMGDIR/obspy
}

@test "$EXAMPLE_TAG/runtests" {
    ch-run $IMG -- bash -c '. activate && obspy-runtests -d'
}
