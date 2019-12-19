load ../../../test/common

setup () {
    scope skip  # issue #64
    prerequisites_ok obspy
}

@test "${ch_tag}/runtests" {
    # Some tests try to use the network even when they're not supposed to. I
    # reported this as a bug on ObsPy [1]. In the meantime, exclude the
    # modules with those tests. This is pretty heavy handed, as only three
    # tests in these two modules have this problem, but I couldn't find a
    # finer-grained exclusion mechanism.
    #
    # [1]: https://github.com/obspy/obspy/issues/1660
    ch-run "$ch_img" -- bash -c '. activate && obspy-runtests -d -x core -x signal'
}
