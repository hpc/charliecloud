load ../common

# NOTE: ls(1) output is not checked; this is for copy-paste into docs

# shellcheck disable=SC2034
tag=RSYNC

setup () {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
    fixtures=$BATS_TMPDIR/rsync
    context=$fixtures/ctx
    context_out=$fixtures/ctx-out
    context_doc=$fixtures/doc
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
          find . -mindepth 1 -printf '%M %n %3s%y  %P -> %l\n' \
        | LC_ALL=C sort -k4 \
        | sed -E -e 's|\w+/|  |g' \
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
    echo file-top > file-top

    # basic example
    cd "$context"
    mkdir basic1
    echo file-basic1 > basic1/file-basic1
    chmod 607 basic1/file-basic1  # weird permissions
    mkdir basic2
    echo file-basic2 > basic2/file-basic2

    # # outside context
    # cd "$context_out"
    # echo file-out > file-out
    # mkdir dir-out
    # echo dir-out.file-out > dir-out/dir-out.file-out
    # ln -s file-out link.out2out
    # cd ..

    # # inside context
    # cd "$context"
    # echo file-ctx > file-ctx
    # mkdir src
    # echo src.file > src/src.file
    # mkdir src/src.dir
    # echo src.dir.file > src/src.dir/src.dir.file
    # mkdir not-src
    # echo not-src.file > not-src.file

    # # symlinks to inside source
    # cd src
    # # to file
    # ln -s src.file src.file_direct
    # ln -s ../src/src.file src.file_up_over
    # ln -s "$context"/src/src.file src.file_abs
    # # relative to directory
    # ln -s src.dir src.dir_direct
    # ln -s ../src/src.dir src.dir_upover
    # ln -s "$context"/src/src.dir src.dir_abs

    # # symlinks to outside source but inside context
    # ln -s ../file-ctx file-ctx_up
    # ln -s "$context"/file-ctx file-ctx_abs
    # ln -s ../not-src not-src_up
    # ln -s "$context"/not-src not-src_abs

    # # symlinks to outside context
    # ln -s ../../ctx-out/file-out file-out_rel
    # ln -s "$context_out"/file-out file-out_abs
    # ln -s ../../ctx-out/dir-out dir-out_rel
    # ln -s "$context_out"/dir-out dir-out_abs

    echo "## created fixtures ##"
    ls_ "$fixtures"
}

@test "${tag}: basic examples" {
    # files
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst

# single file
RSYNC /basic1/file-basic1 /dst
# ... renamed
RSYNC /basic1/file-basic1 /dst/file-basic1_renamed
# ... without metadata
RSYNC +z /basic1/file-basic1 /dst/file-basic1_nom
# ... with trailing slash on *destination*
RSYNC /basic1/file-basic1 /dst/new/
EOF
    ch-image build -f "$ch_tmpimg_df" "$context"
    ( cd "$CH_IMAGE_STORAGE/img/tmpimg/dst" && ls -lhR . )
    run ls_ "$CH_IMAGE_STORAGE/img/tmpimg/dst"
    echo "$output"
    [[ $status -eq -0 ]]
cat <<EOF | diff -u - <(echo "$output")
-rw----rwx 1  12  file-basic1
-rw------- 1  12  file-basic1_nom
-rw----rwx 1  12  file-basic1_renamed
drwxrwx--- 1      new
-rw----rwx 1  12    file-basic1
EOF

    # single directory
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst

# directory
RSYNC /basic1 /dst
# ... renamed?
RSYNC /basic1 /dst/basic1_new
# ... renamed (trailing slash on source)
RSYNC /basic1/ /dst/basic1_renamed
# ... destination trailing slash has no effect for directory sources
RSYNC /basic1 /dst/basic1_newB
RSYNC /basic1/ /dst/basic1_renamedB/
# ... with +z (no-op!!)
RSYNC +z /basic1 /dst/basic1_newC
# ... need -r at least
RSYNC +z -r /basic1/ /dst/basic1_newD
EOF
    ch-image build -f "$ch_tmpimg_df" "$context"
    ( cd "$CH_IMAGE_STORAGE/img/tmpimg/dst" && ls -lhR . )
    run ls_ "$CH_IMAGE_STORAGE/img/tmpimg/dst"
    echo "$output"
    [[ $status -eq -0 ]]
cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      basic1
-rw----rwx 1  12    file-basic1
drwxrwx--- 1      basic1_new
drwxrwx--- 1        basic1
-rw----rwx 1  12      file-basic1
drwxrwx--- 1      basic1_newB
drwxrwx--- 1        basic1
-rw----rwx 1  12      file-basic1
drwxrwx--- 1      basic1_newD
-rw------- 1  12    file-basic1
drwxrwx--- 1      basic1_renamed
-rw----rwx 1  12    file-basic1
drwxrwx--- 1      basic1_renamedB
-rw----rwx 1  12    file-basic1
EOF

    # multiple directories
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst

# two directories explicitly
RUN mkdir /dst/dstB && echo file-dstB > /dst/dstB/file-dstB
RSYNC /basic1 /basic2 /dst/dstB
# ... with wildcards
RUN mkdir /dst/dstC && echo file-dstC > /dst/dstC/file-dstC
RSYNC /basic* /dst/dstC
# ... with trailing slashes
RUN mkdir /dst/dstD && echo file-dstD > /dst/dstD/file-dstD
RSYNC /basic1/ /basic2/ /dst/dstD
# ... with trailing slashes and wildcards
RUN mkdir /dst/dstE && echo file-dstE > /dst/dstE/file-dstE
RSYNC /basic*/ /dst/dstE
# ... with one trailing slash and one not
RUN mkdir /dst/dstF && echo file-dstF > /dst/dstF/file-dstF
RSYNC /basic1 /basic2/ /dst/dstF
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ( cd "$CH_IMAGE_STORAGE/img/tmpimg/dst" && ls -lhR . )
    run ls_ "$CH_IMAGE_STORAGE/img/tmpimg/dst"
    echo "$output"
    [[ $status -eq -0 ]]
cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      dstB
drwxrwx--- 1        basic1
-rw----rwx 1  12      file-basic1
drwxrwx--- 1        basic2
-rw-rw---- 1  12      file-basic2
-rw-rw---- 1  10    file-dstB
drwxrwx--- 1      dstC
drwxrwx--- 1        basic1
-rw----rwx 1  12      file-basic1
drwxrwx--- 1        basic2
-rw-rw---- 1  12      file-basic2
-rw-rw---- 1  10    file-dstC
drwxrwx--- 1      dstD
-rw----rwx 1  12    file-basic1
-rw-rw---- 1  12    file-basic2
-rw-rw---- 1  10    file-dstD
drwxrwx--- 1      dstE
-rw----rwx 1  12    file-basic1
-rw-rw---- 1  12    file-basic2
-rw-rw---- 1  10    file-dstE
drwxrwx--- 1      dstF
drwxrwx--- 1        basic1
-rw----rwx 1  12      file-basic1
-rw-rw---- 1  12    file-basic2
-rw-rw---- 1  10    file-dstF
EOF
}

# symlink stuff?
# symlink between src1 and src2
# hard links
# top of transfer with just a file
# replace directory (i.e., don't merge)

# no options
# +
# +L
# +L renamed
# +L with slash
# -rl --copy-unsafe-links
# single file
# single file with trailing slash on *destination*
# file and directory

