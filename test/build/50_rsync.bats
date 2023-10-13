load ../common

# NOTE: ls(1) output is not checked; this is for copy-paste into docs

# shellcheck disable=SC2034
tag=RSYNC

setup () {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
    umask 0007
    fixtures=$BATS_TMPDIR/rsync
    context=$fixtures/ctx
    dst=$CH_IMAGE_STORAGE/img/tmpimg/dst
}

ls_ () {
    # ls(1)-alike but more predictable output and only the fields we want. See
    # also “compare-ls” in ch-convert.bats.
    (
        cd "$1"
          find . -mindepth 1 -printf '%M %n %3s%y  %P -> %l\n' \
        | LC_ALL=C sort -k4 \
        | sed -E -e 's#  ([[:alnum:]._-]+/){4}#          #' \
                 -e 's#  ([[:alnum:]._-]+/){3}#        #' \
                 -e 's#  ([[:alnum:]._-]+/){2}#      #' \
                 -e 's#  ([[:alnum:]._-]+/){1}#    #' \
                 -e 's# -> $##' \
                 -e 's#([0-9]+)[f]#\1#' \
                 -e 's#([0-9]+ )[0-9 ]+[a-z] #\1    #' \
                 -e "s#$1#/...#"
    )
}

ls_dump () {
    target=$1
    target_basename=$(basename "$target")
    target_parent=$(dirname "$target")
    out_basename=$2

    (    cd "$target_parent" \
      && ls -oghR "$target_basename" > "${BATS_TMPDIR}/rsync_${out_basename}" )
}


@test "${tag}: set up fixtures" {
    rm -Rf --one-file-system "$fixtures"
    mkdir "$fixtures"
    cd "$fixtures"
    mkdir "$context"

    # outside context
    echo file-out > file-out
    mkdir dir-out
    echo dir-out.file > dir-out/dir-out.file

    # top level of context
    cd "$context"
    printf 'basic1/file-basic1\nbasic2\n' > file-top  # also list of files
    mkdir dir-top
    echo dir-top.file > dir-top/dir-top.file

    # plain files and directories
    mkdir basic1
    chmod 705 basic1              # weird permissions
    echo file-basic1 > basic1/file-basic1
    chmod 604 basic1/file-basic1  # weird permissions
    mkdir basic2
    echo file-basic2 > basic2/file-basic2

    # symlinks
    cd "$context"
    mkdir sym2
    echo file-sym2 > sym2/file-sym2
    mkdir sym1
    cd sym1
    echo file-sym1 > file-sym1
    mkdir dir-sym1
    echo dir-sym1.file > dir-sym1/dir-sym1.file
    # target outside context
    ln -s "$fixtures"/file-out file-out_abs
    ln -s ../../file-out file-out_rel
    ln -s ../../dir-out dir-out_rel
    # target outside source (but inside context)
    ln -s "$context"/file-top file-top_abs
    ln -s ../file-top file-top_rel
    ln -s ../dir-top dir-top_rel
    # target inside source
    ln -s "$context"/sym1/file-sym1 file-sym1_abs
    ln -s file-sym1 file-sym1_direct
    ln -s ../sym1/file-sym1 file-sym1_upover
    ln -s dir-sym1 dir-sym1_direct
    # target inside other source
    ln -s "$context"/sym2/file-sym2 file-sym2_abs
    ln -s ../sym2/file-sym2 file-sym2_upover

    # broken symlink
    cd "$context"
    mkdir sym-broken
    cd sym-broken
    ln -s doesnotexist doesnotexist_broken_direct

    # hard links
    cd "$context"
    mkdir hard
    cd hard
    echo hard-file > hard-file1
    ln hard-file1 hard-file2

    echo "## created fixtures ##"
    ls_ "$fixtures"
    ls_ "$fixtures" > $BATS_TMPDIR/rsync_fixtures-ls_
    ls_dump "$fixtures" fixtures
}


@test "${tag}: source: file(s)" {
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
# multiple files
RSYNC /basic1/file-basic1 /basic2/file-basic2 /dst/newB
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ls_dump "$dst" files
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq -0 ]]
    cat <<EOF | diff -u - <(echo "$output")
-rw----r-- 1  12  file-basic1
-rw------- 1  12  file-basic1_nom
-rw----r-- 1  12  file-basic1_renamed
drwxrwx--- 1      new
-rw----r-- 1  12    file-basic1
drwxrwx--- 1      newB
-rw----r-- 1  12    file-basic1
-rw-rw---- 1  12    file-basic2
EOF
}


@test "${tag}: source: one directory" {
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
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ls_dump "$dst" dir1
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq -0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwx---r-x 1      basic1
-rw----r-- 1  12    file-basic1
drwxrwx--- 1      basic1_new
drwx---r-x 1        basic1
-rw----r-- 1  12      file-basic1
drwxrwx--- 1      basic1_newB
drwx---r-x 1        basic1
-rw----r-- 1  12      file-basic1
drwx------ 1      basic1_newD
-rw------- 1  12    file-basic1
drwx---r-x 1      basic1_renamed
-rw----r-- 1  12    file-basic1
drwx---r-x 1      basic1_renamedB
-rw----r-- 1  12    file-basic1
EOF
}


@test "${tag}: source: multiple directories" {
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
# ... replace (do not merge with) existing contents
RUN mkdir /dst/dstG && echo file-dstG > /dst/dstG/file-dstG
RSYNC --delete /basic*/ /dst/dstG
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ls_dump "$dst" dir2
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq -0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      dstB
drwx---r-x 1        basic1
-rw----r-- 1  12      file-basic1
drwxrwx--- 1        basic2
-rw-rw---- 1  12      file-basic2
-rw-rw---- 1  10    file-dstB
drwxrwx--- 1      dstC
drwx---r-x 1        basic1
-rw----r-- 1  12      file-basic1
drwxrwx--- 1        basic2
-rw-rw---- 1  12      file-basic2
-rw-rw---- 1  10    file-dstC
drwx---r-x 1      dstD
-rw----r-- 1  12    file-basic1
-rw-rw---- 1  12    file-basic2
-rw-rw---- 1  10    file-dstD
drwx---r-x 1      dstE
-rw----r-- 1  12    file-basic1
-rw-rw---- 1  12    file-basic2
-rw-rw---- 1  10    file-dstE
drwxrwx--- 1      dstF
drwx---r-x 1        basic1
-rw----r-- 1  12      file-basic1
-rw-rw---- 1  12    file-basic2
-rw-rw---- 1  10    file-dstF
drwx---r-x 1      dstG
-rw----r-- 1  12    file-basic1
-rw-rw---- 1  12    file-basic2
EOF
}


@test "${tag}: source: /" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst

RSYNC / /dst
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ls_dump "$dst" dir-root
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq -0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwx---r-x 1      basic1
-rw----r-- 1  12    file-basic1
drwxrwx--- 1      basic2
-rw-rw---- 1  12    file-basic2
drwxrwx--- 1      dir-top
-rw-rw---- 1  13    dir-top.file
-rw-rw---- 1  26  file-top
drwxrwx--- 1      hard
-rw-rw---- 2  10    hard-file1
-rw-rw---- 2  10    hard-file2
drwxrwx--- 1      sym-broken
lrwxrwxrwx 1        doesnotexist_broken_direct -> doesnotexist
drwxrwx--- 1      sym1
drwxrwx--- 1        dir-sym1
-rw-rw---- 1  14      dir-sym1.file
lrwxrwxrwx 1        dir-sym1_direct -> dir-sym1
lrwxrwxrwx 1        dir-top_rel -> ../dir-top
-rw-rw---- 1  10    file-sym1
lrwxrwxrwx 1        file-sym1_direct -> file-sym1
lrwxrwxrwx 1        file-sym1_upover -> ../sym1/file-sym1
lrwxrwxrwx 1        file-sym2_upover -> ../sym2/file-sym2
lrwxrwxrwx 1        file-top_rel -> ../file-top
drwxrwx--- 1      sym2
-rw-rw---- 1  10    file-sym2
EOF
}


@test "${tag}: symlinks: default" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC /sym1 /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ 0 -eq $(echo "$output" | grep -F 'skipping non-regular file' | wc -l) ]]
    ls_dump "$dst" sym-default
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      sym1
drwxrwx--- 1        dir-sym1
-rw-rw---- 1  14      dir-sym1.file
lrwxrwxrwx 1        dir-sym1_direct -> dir-sym1
lrwxrwxrwx 1        dir-top_rel -> ../dir-top
-rw-rw---- 1  10    file-sym1
lrwxrwxrwx 1        file-sym1_direct -> file-sym1
lrwxrwxrwx 1        file-sym1_upover -> ../sym1/file-sym1
lrwxrwxrwx 1        file-sym2_upover -> ../sym2/file-sym2
lrwxrwxrwx 1        file-top_rel -> ../file-top
EOF
}


@test "${tag}: symlinks: default, source trailing slash" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC /sym1/ /dst/sym1
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ls_dump "$dst" sym-slashed
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      sym1
drwxrwx--- 1        dir-sym1
-rw-rw---- 1  14      dir-sym1.file
lrwxrwxrwx 1        dir-sym1_direct -> dir-sym1
-rw-rw---- 1  10    file-sym1
lrwxrwxrwx 1        file-sym1_direct -> file-sym1
EOF
}


@test "${tag}: symlinks: +m" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC +m /sym1/ /dst/sym1
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ 12 -eq $(echo "$output" | grep -F 'skipping non-regular file' | wc -l) ]]
    ls_dump "$dst" sym-m
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      sym1
drwxrwx--- 1        dir-sym1
-rw-rw---- 1  14      dir-sym1.file
-rw-rw---- 1  10    file-sym1
EOF
}


@test "${tag}: symlinks: +u" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC +u /sym1/ /dst/sym1
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ls_dump "$dst" sym-u
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      sym1
drwxrwx--- 1        dir-out_rel
-rw-rw---- 1  13      dir-out.file
drwxrwx--- 1        dir-sym1
-rw-rw---- 1  14      dir-sym1.file
lrwxrwxrwx 1        dir-sym1_direct -> dir-sym1
drwxrwx--- 1        dir-top_rel
-rw-rw---- 1  13      dir-top.file
-rw-rw---- 1   9    file-out_abs
-rw-rw---- 1   9    file-out_rel
-rw-rw---- 1  10    file-sym1
-rw-rw---- 1  10    file-sym1_abs
lrwxrwxrwx 1        file-sym1_direct -> file-sym1
-rw-rw---- 1  10    file-sym1_upover
-rw-rw---- 1  10    file-sym2_abs
-rw-rw---- 1  10    file-sym2_upover
-rw-rw---- 1  26    file-top_abs
-rw-rw---- 1  26    file-top_rel
EOF
}


@test "${tag}: symlinks: between sources" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC /sym1 /sym2 /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-between
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      sym1
drwxrwx--- 1        dir-sym1
-rw-rw---- 1  14      dir-sym1.file
lrwxrwxrwx 1        dir-sym1_direct -> dir-sym1
lrwxrwxrwx 1        dir-top_rel -> ../dir-top
-rw-rw---- 1  10    file-sym1
lrwxrwxrwx 1        file-sym1_direct -> file-sym1
lrwxrwxrwx 1        file-sym1_upover -> ../sym1/file-sym1
lrwxrwxrwx 1        file-sym2_upover -> ../sym2/file-sym2
lrwxrwxrwx 1        file-top_rel -> ../file-top
drwxrwx--- 1      sym2
-rw-rw---- 1  10    file-sym2
EOF
}


@test "${tag}: symlinks: sources are symlinks to file" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC /sym1/file-sym1_direct /sym1/file-sym1_upover /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-to-file
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
lrwxrwxrwx 1      file-sym1_direct -> file-sym1
EOF
}


@test "${tag}: symlinks: source is symlink to directory" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC /sym1/dir-sym1_direct /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-to-dir
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
lrwxrwxrwx 1      dir-sym1_direct -> dir-sym1
EOF
}


@test "${tag}: symlinks: source is symlink to directory (trailing slash)" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC /sym1/dir-sym1_direct/ /dst/dir-sym1_direct
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-to-dir-slashed
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      dir-sym1_direct
-rw-rw---- 1  14    dir-sym1.file
EOF
}


@test "${tag}: symlinks: broken" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC /sym-broken /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-broken
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      sym-broken
lrwxrwxrwx 1        doesnotexist_broken_direct -> doesnotexist
EOF
}


@test "${tag}: symlinks: broken (--copy-links)" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC +m --copy-links /sym-broken /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"symlink has no referent: \"${context}/sym-broken/doesnotexist_broken_direct\""* ]]
}


@test "${tag}: symlinks: src file, dst symlink to file" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst \
 && touch /dst/file-dst \
 && ln -s file-dst /dst/file-dst_direct \
 && ls -lh /dst
RSYNC /file-top /dst/file-dst_direct
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-dst-symlink-file
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
-rw-rw---- 1   0  file-dst
-rw-rw---- 1  26  file-dst_direct
EOF
}


@test "${tag}: symlinks: src file, dst symlink to dir" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst \
 && mkdir /dst/dir-dst \
 && ln -s dir-dst /dst/dir-dst_direct \
 && ls -lh /dst
RSYNC /file-top /dst/dir-dst_direct
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-dst-symlink-dir-src-file
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      dir-dst
-rw-rw---- 1  26    file-top
lrwxrwxrwx 1      dir-dst_direct -> dir-dst
EOF
}


@test "${tag}: symlinks: src dir, dst symlink to dir" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst \
 && mkdir /dst/dir-dst \
 && ln -s dir-dst /dst/dir-dst_direct \
 && ls -lh /dst
RSYNC /dir-top /dst/dir-dst_direct
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-dst-symlink-dir
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      dir-dst
drwxrwx--- 1        dir-top
-rw-rw---- 1  13      dir-top.file
lrwxrwxrwx 1      dir-dst_direct -> dir-dst
EOF
}


@test "${tag}: symlinks: src dir (slashed), dst symlink to dir" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst \
 && mkdir /dst/dir-dst \
 && ln -s dir-dst /dst/dir-dst_direct \
 && ls -lh /dst
RSYNC /dir-top/ /dst/dir-dst_direct
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" sym-dst-symlink-dir-slashed
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      dir-dst
-rw-rw---- 1  13    dir-top.file
lrwxrwxrwx 1      dir-dst_direct -> dir-dst
EOF
}


@test "${tag}: hard links" {
    inode_src=$(stat -c %i "$context"/hard/hard-file1)
    [[ $inode_src -eq $(stat -c %i "$context"/hard/hard-file2) ]]
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC /hard /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 0 ]]
    ls_dump "$dst" hard
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq 0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwxrwx--- 1      hard
-rw-rw---- 2  10    hard-file1
-rw-rw---- 2  10    hard-file2
EOF
    inode_dst=$(stat -c %i "$CH_IMAGE_STORAGE"/img/tmpimg/dst/hard/hard-file1)
    [[     $inode_dst \
       -eq $(stat -c %i "$CH_IMAGE_STORAGE"/img/tmpimg/dst/hard/hard-file2) ]]
    [[ $inode_src -ne $inode_dst ]]
}


@test "${tag}: relative paths" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
WORKDIR /dst
RSYNC file-basic1 .
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"/basic1
    ls_dump "$dst" files
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq -0 ]]
    cat <<EOF | diff -u - <(echo "$output")
-rw----r-- 1  12  file-basic1
EOF
}


@test "${tag}: no context" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RSYNC foo bar
EOF
    run ch-image build -t tmpimg - < "$ch_tmpimg_df"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: no context'* ]]
}


@test "${tag}: bad + option" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RSYNC +y foo bar
EOF
    run ch-image build -t tmpimg - < "$ch_tmpimg_df"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: invalid plus option: y'* ]]
}


@test "${tag}: remote transports" {
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RSYNC foo://bar baz
EOF
    run ch-image build -t tmpimg - < "$ch_tmpimg_df"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: SSH and rsync transports not supported'* ]]
}


@test "${tag}: excluded options" {
    # We only test one of them, for DRY, though I did pick the one that seemed
    # most dangerous.
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RSYNC --remove-source-files foo bar
EOF
    run ch-image build -t tmpimg - < "$ch_tmpimg_df"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: disallowed option: --remove-source-files'* ]]

}

@test "${tag}: --*-from translation" {
    # relative (context)
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RSYNC --files-from=./file-top / /dst
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ls_dump "$dst" files
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq -0 ]]
    cat <<EOF | diff -u - <(echo "$output")
drwx---r-x 1      basic1
-rw----r-- 1  12    file-basic1
drwxrwx--- 1      basic2
-rw-rw---- 1  12    file-basic2
EOF

    # absolute (image)
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RUN mkdir /dst
RUN printf 'file-top\n' > /fls
RSYNC --files-from=/fls / /dst
EOF
    ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    ls_dump "$dst" files
    run ls_ "$dst"
    echo "$output"
    [[ $status -eq -0 ]]
    cat <<EOF | diff -u - <(echo "$output")
-rw-rw---- 1  26  file-top
EOF

    # bare hyphen disallowed
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RSYNC --files-from=- / /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: --*-from: can'?'t use standard input'* ]]

    # colon disallowed
    cat <<EOF > "$ch_tmpimg_df"
FROM alpine:3.17
RSYNC --files-from=foo:bar / /dst
EOF
    run ch-image build --rebuild -f "$ch_tmpimg_df" "$context"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: --*-from: can'?'t use remote hosts'* ]]
}
