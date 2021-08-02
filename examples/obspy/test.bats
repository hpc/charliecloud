true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

setup () {
    scope quick
    prerequisites_ok obspy
}

@test "${ch_tag}/runtests" {
    # Reid: Some tests try to use the network even when they're not supposed 
    # to. I reported this as a bug on ObsPy [1]. In the meantime, exclude the
    # modules with those tests. This is pretty heavy handed, as only three
    # tests in these two modules have this problem, but I couldn't find a
    # finer-grained exclusion mechanism.
    #
    # Rusty: They eventually provided _a_ solution [2], but it doesn't actually
    # address our issue since it requires at least one run with network access.
    # 
    # Obspy-runtest writes some inf to a directory so we bind to a tmpdir instead
    # Bind a tmpdir instead.
    # [1]: https://github.com/obspy/obspy/issues/1660
    # [2]: https://github.com/obspy/obspy/pull/1663
    #
    tmp_data=$(mktemp -d)
    # Test fails since obspy tries to write files to this directory
    data_dir="/usr/lib/python3.7/site-packages/obspy/clients/filesystem/tests/data/tsindex_data"
    # Make a copy of the directory that we'll have write privileges over and bind mount it. 
    cp -r "$ch_img""$data_dir" "$tmp_data"
    ch-run --bind "$tmp_data":"$data_dir" "$ch_img" -- bash -c '. activate && obspy-runtests -d -x core -x signal'
}
