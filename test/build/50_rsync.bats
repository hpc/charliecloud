load ../common

# shellcheck disable=SC2034
tag=RSYNC

setup () {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
    fixtures=$BATS_TMPDIR/rsync
    context=$fixtures/ctx
    context_out=$fixtures/ctx-out
    if [[ -e $fixtures ]]; then
        echo '## input ##'
        ls_ "$fixtures"
    fi
}

ls_ () {
    # ls(1)-alike but more predictable output and only the fields we want. See
    # also “compare-ls” in ch-convert.bats.
    (
        cd "$1"
          find . -mindepth 1 -printf '%M %n %3s%y  :%d:%f -> %l\n' \
        | sed -E -e 's|:1:||' \
                 -e 's|:2:|  |' \
                 -e 's|:3:|    |' \
                 -e 's|:4:|      |' \
                 -e 's| -> $||' \
                 -e 's|([0-9]+)[f]|\1|' \
                 -e 's|([0-9]+ )[0-9 ]+[a-z] |\1    |' \
                 -e "s|$1|/...|"
    )
}


@test "${tag}: set up fixtures" {
    rm -Rf --one-file-system "$fixtures"
    mkdir "$fixtures"
    cd "$fixtures"

    # top level
    mkdir "$context"
    mkdir "$context_out"
    ln -s "$context" "$fixtures"/ctx_direct

    # outside context
    cd "$context_out"
    echo file-out > file-out
    mkdir dir-out
    echo dir-out.file-out > dir-out/dir-out.file-out
    ln -s file-out link.out2out
    cd ..

    # inside context
    cd "$context"
    echo file-ctx > file-ctx
    mkdir src
    echo src.file > src/src.file
    mkdir src/src.dir
    echo src.dir.file > src/src.dir/src.dir.file
    mkdir not-src
    echo not-src.file > not-src.file

    # symlinks to inside source
    cd src
    # to file
    ln -s src.file src.file_direct
    ln -s ../src/src.file src.file_up_over
    ln -s "$context"/src/src.file src.file_abs
    # relative to directory
    ln -s src.dir src.dir_direct
    ln -s ../src/src.dir src.dir_upover
    ln -s "$context"/src/src.dir src.dir_abs

    # symlinks to outside source but inside context
    ln -s ../file-ctx file-ctx_up
    ln -s "$context"/file-ctx file-ctx_abs
    ln -s ../not-src not-src_up
    ln -s "$context"/not-src not-src_abs

    # symlinks to outside context
    ln -s ../../ctx-out/file-out file-out_rel
    ln -s "$context_out"/file-out file-out_abs
    ln -s ../../ctx-out/dir-out dir-out_rel
    ln -s "$context_out"/dir-out dir-out_abs

    # hard links
    echo hard1 > hard1
    ln hard1 hard2

    # weird permissions
    touch weird-perms-607 > weird-perms-607
    chmod 607 weird-perms-607

    echo "## created fixtures ##"
    ls_ "$fixtures"
    false
}

# no options
# +
# +L
# +L renamed
# +L with slash
# -rl --copy-unsafe-links
# single file
# file and directory

# ssh: transport
#   ssh -o batchmode=yes localhost true
# rsync: transport
#   $ rsync --info=progress2 'rsync://archive.kernel.org/debian-archive/debian/dists/buzz/main/binary-i386/editors/e[de]*.deb' /tmp
#   $ ls -lh /tmp/*.deb
#   -rw-r----- 1 reidpr reidpr 98K Sep 14 14:17 /tmp/ed-0.2-11.deb
#   -rw-r----- 1 reidpr reidpr 39K Sep 14 14:17 /tmp/ee-126.1.89-1.deb
