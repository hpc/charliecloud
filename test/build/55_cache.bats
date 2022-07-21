load ../common

# shellcheck disable=SC2034
tag=cache

# WARNING: Git timestamp precision is only one second [1]. This can cause
# unstable sorting within --tree output because the tests commit very fast. If
# it matters, add a “sleep 1”.
#
# [1]: https://stackoverflow.com/questions/28237043


treeonly () {
    # Remove (1) everything including and after first blank line and (2)
    # trailing whitespace on each line.
    sed -E -e '/^$/Q' -e 's/\s+$//'
}

setup () {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
    [[ $CH_IMAGE_CACHE = enabled ]] || skip 'build cache enabled only'
    export CH_IMAGE_STORAGE=$BATS_TMPDIR/butest  # don't mess up main storage
    dot_base=$BATS_TMPDIR/bu_
    ch-image gestalt bucache-dot
}


### Test cases that go in the paper ###

@test "${tag}: §3.1 empty cache" {
    rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

    blessed_tree=$(cat << EOF
initializing storage directory: v3 ${CH_IMAGE_STORAGE}
initializing empty build cache
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}empty"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}


@test "${tag}: §3.2.1 initial pull" {
    ch-image pull alpine:3.9

    blessed_tree=$(cat << 'EOF'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}initial-pull"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}


@test "${tag}: §3.5 FROM" {
    # FROM pulls
    ch-image build-cache --reset
    run ch-image build -v -t d -f bucache/from.df .
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1. FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (d, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}from"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)

    # FROM doesn't pull (same target name)
    run ch-image build -v -t d -f bucache/from.df .
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (d, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)

    # FROM doesn't pull (different target name)
    run ch-image build -v -t d2 -f bucache/from.df .
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (d2, d, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}


@test "${tag}: §3.3.1 Dockerfile A" {
    ch-image build-cache --reset

    ch-image build -t a -f bucache/a.df .

    blessed_out=$(cat << 'EOF'
*  (a) RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}a"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: §3.3.2 Dockerfile B" {
    ch-image build-cache --reset

    ch-image build -t a -f bucache/a.df .
    ch-image build -t b -f bucache/b.df .

    blessed_out=$(cat << 'EOF'
*  (b) RUN echo baz
*  (a) RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}b"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: §3.3.3 Dockerfile C" {
    ch-image build-cache --reset

    ch-image build -t a -f bucache/a.df .
    ch-image build -t b -f bucache/b.df .
    sleep 1
    ch-image build -t c -f bucache/c.df .

    blessed_out=$(cat << 'EOF'
*  (c) RUN echo qux
| *  (b) RUN echo baz
| *  (a) RUN echo bar
|/
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}c"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: rebuild A" {
    # Forcing a rebuild show produce a new pair of FOO and BAR commits from
    # from the alpine branch.
    blessed_out=$(cat << 'EOF'
*  (a) RUN echo bar
*  RUN echo foo
| *  (c) RUN echo qux
| | *  (b) RUN echo baz
| | *  RUN echo bar
| |/
| *  RUN echo foo
|/
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    ch-image --rebuild build -t a -f bucache/a.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    echo "$output"
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: rebuild B" {
    # Rebuild of B. Since A was rebuilt in the last test, and because
    # the rebuild behavior only forces misses on non-FROM instructions, it
    # should now be based on A's new commits.
    blessed_out=$(cat << 'EOF'
*  (b) RUN echo baz
*  (a) RUN echo bar
*  RUN echo foo
| *  (c) RUN echo qux
| | *  RUN echo baz
| | *  RUN echo bar
| |/
| *  RUN echo foo
|/
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    ch-image --rebuild build -t b -f bucache/b.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: rebuild C" {
    # Rebuild C. Since C doesn't reference img_a (like img_b does) rebuilding
    # causes a miss on FOO. Thus C makes new FOO and QUX commits.
    #
    # Shouldn't FOO hit? --reidpr 2/16
    #  - No! Rebuild forces misses; since c.df has it's own FOO it should miss.
    #     --jogas 2/24
    blessed_out=$(cat << 'EOF'
*  (c) RUN echo qux
*  RUN echo foo
| *  (b) RUN echo baz
| *  (a) RUN echo bar
| *  RUN echo foo
|/
| *  RUN echo qux
| | *  RUN echo baz
| | *  RUN echo bar
| |/
| *  RUN echo foo
|/
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    ch-image --rebuild build -t c -f bucache/c.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}: §3.7 change then revert" {
    ch-image build-cache --reset

    ch-image build -t e -f bucache/a.df .
    # “change” by using a different Dockerfile
    sleep 1
    ch-image build -t e -f bucache/c.df .

    blessed_out=$(cat << 'EOF'
*  (e) RUN echo qux
| *  RUN echo bar
|/
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}revert1"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # “revert change”; no need to check for miss b/c it will show up in graph
    ch-image build -t e -f bucache/a.df .

    blessed_out=$(cat << 'EOF'
*  RUN echo qux
| *  (e) RUN echo bar
|/
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}revert2"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: §3.4.1 two pulls, same" {
    ch-image build-cache --reset
    ch-image pull alpine:3.9
    ch-image pull alpine:3.9

    blessed_out=$(cat << 'EOF'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: §3.4.2 two pulls, different" {
    localregistry_init
    unset CH_IMAGE_AUTH  # don’t give local creds to Docker Hub

    # Simulate a change in an image from a remote repo; ensure that “ch-image
    # pull” downloads the next image. Note ch-image pull behavior is the same
    # with or without the build cache. This test is here for two reasons:
    #
    #    1. The build cache interactions with pull is more complex, i.e., we
    #       assume that if pull works here with the cache enabled, it also
    #       works without it.
    #
    #    2. We emit debugging PDFs for use in the paper, and doing that
    #       anywhere else would be too surprising.

    df_ours=$(cat <<'EOF'
FROM localhost:5000/champ
RUN cat /worldchampion
EOF
)
    tree_ours_before=$(cat <<'EOF'
*  (wc) RUN cat /worldchampion
*  (localhost+5000%champ) PULL localhost:5000/champ
*  (HEAD -> root) ROOT
EOF
)

    echo
    echo '*** Prepare “ours” and “theirs” storages.'
    so=$BATS_TMPDIR/pull-local
    st=$BATS_TMPDIR/pull-remote
    rm -Rf --one-file-system "$so" "$st"

    echo
    echo '*** Them: Create the initial image state.'
    ch-image -s "$st" build -v -t capablanca -f - . <<EOF
FROM alpine:3.9
RUN echo josé > /worldchampion
EOF
    ch-image -s "$st" --auth --tls-no-verify \
             push capablanca localhost:5000/champ

    echo '*** Us: Build image using theirs as base.'
    # Both download and build caches are cold; FROM will do a (lazy) pull.
    # Files should be downloaded and all instructions should miss. Then do it
    # again; nothing should download and it should be all hits.
    run ch-image -s "$so" --auth --tls-no-verify \
                 build -t wc -f <(echo "$df_ours") /tmp
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'. FROM'* ]]
    [[ $output = *'manifest list: downloading'* ]]
    [[ $output = *'manifest: downloading'* ]]
    [[ $output = *'config: downloading'* ]]
    [[ $output = *'. RUN'* ]]
    run ch-image -s "$so" --tls-no-verify build -t wc -f <(echo "$df_ours") /tmp
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output != *'manifest list: downloading'* ]]
    [[ $output != *'manifest: downloading'* ]]
    [[ $output != *'config: downloading'* ]]
    [[ $output = *'* RUN'* ]]
    run ch-image -s "$so" build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$tree_ours_before") <(echo "$output" | treeonly)

    echo
    echo '*** Us: explicit (eager) pull.'
    # This should download the manifest list and manifest, see that there are
    # no changes, and not download the config or layers.
    run ch-image -s "$so" --auth --tls-no-verify pull localhost:5000/champ
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'manifest list: downloading'* ]]
    [[ $output = *'manifest: downloading'* ]]
    [[ $output = *'config: using existing file'* ]]
    [[ $output = *'layer'*'using existing file'* ]]
    run ch-image -s "$so" build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$tree_ours_before") <(echo "$output" | treeonly)

    echo
    echo '*** Them: Change and push the image.'
    ch-image -s "$st" build -t fischer -f - . <<EOF
FROM alpine:3.9
RUN echo "bobby" > /worldchampion
EOF
    ch-image -s "$st" --auth --tls-no-verify push fischer localhost:5000/champ

    echo
    echo '*** Us: Rebuild our image (lazy pull does not update).'
    # FROM should not notice the updated remote image.
    run ch-image -s "$so" --tls-no-verify build -t wc -f <(echo "$df_ours") /tmp
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output != *'manifest list: downloading'* ]]
    [[ $output != *'manifest: downloading'* ]]
    [[ $output != *'config: downloading'* ]]
    [[ $output = *'* RUN'* ]]
    run ch-image -s "$so" build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$tree_ours_before") <(echo "$output" | treeonly)

    echo
    echo '*** Us: Explicitly pull updated image.'
    # Returned config hash should differ from what is in storage; thus, the
    # new layer(s) should be pulled and the image branch in the cache updated.
    run ch-image -s "$so" --auth --tls-no-verify pull localhost:5000/champ
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'manifest list: downloading'* ]]
    [[ $output = *'manifest: downloading'* ]]
    [[ $output = *'config: downloading'* ]]
    [[ $output = *'layer'*'downloading:'*'100%'* ]]
    run ch-image -s "$so" build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u - <(echo "$output" | treeonly) <<'EOF'
*  (localhost+5000%champ) PULL localhost:5000/champ
| *  (wc) RUN cat /worldchampion
| *  PULL localhost:5000/champ
|/
*  (HEAD -> root) ROOT
EOF

    echo
    echo '*** Us: Rebuild our image (uses updated image).'
    # After the eager pull above, the base image exists in storage. Thus, the
    # FROM instruction hits; however, the resulting SID differs from the
    # original. Thus, intructions after FROM should miss.
    run ch-image -s "$so" --tls-no-verify build -t wc -f <(echo "$df_ours") /tmp
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output != *'manifest list: downloading'* ]]
    [[ $output != *'manifest: downloading'* ]]
    [[ $output != *'config: using existing file'* ]]
    [[ $output = *'. RUN'* ]]
    run ch-image -s "$so" build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u - <(echo "$output" | treeonly) <<'EOF'
*  (wc) RUN cat /worldchampion
*  (localhost+5000%champ) PULL localhost:5000/champ
| *  RUN cat /worldchampion
| *  PULL localhost:5000/champ
|/
*  (HEAD -> root) ROOT
EOF
}

# FIXME: for issue #1359, add test here where they revert the image in the
# remote registry to a previous state; our next pull will hit, and so too
# should any subsequent previously cached instructions based on the FROM SID.

@test "${tag}: branch ready" {
    ch-image build-cache --reset

    # Build A as “foo”.
    ch-image build -t foo -f bucache/a.df ./bucache

    # Rebuild A, except this is a broken version; the second instruction fails
    # leaving the new branch in a not-ready state pointing to “echo foo”.
    # The old branch remains.
    run ch-image build -t foo -f ./bucache/a-fail.df ./bucache
    sleep 1
    echo "$output"
    [[ $status -eq 1 ]]
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    blessed_out=$(cat << 'EOF'
*  (foo) RUN echo bar
*  (foo#) RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # Build C as “foo”. Now branch “foo” points to the completed build of the
    # new Dockerfile, and the not-ready branch is gone.
    ch-image build -t foo -f ./bucache/c.df ./bucache
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    blessed_out=$(cat << 'EOF'
*  (foo) RUN echo qux
| *  RUN echo bar
|/
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: --force" {
    ch-image build-cache --reset

    # Use a centos:7 image because it can install some RPMs without --force.

    # First build, without --force.
    ch-image build -t force -f ./bucache/force.df ./bucache

    # Second build, with --force. This should diverge after the first WORKDIR.
    sleep 1
    ch-image build --force -t force -f ./bucache/force.df ./bucache
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    blessed_out=$(cat << 'EOF'
*  (force) WORKDIR /usr
*  RUN.F yum install -y ed         # doesn't need --force
| *  WORKDIR /usr
| *  RUN yum install -y ed         # doesn't need --force
|/
*  WORKDIR /
*  (centos+7) PULL centos:7
*  (HEAD -> root) ROOT
EOF
)
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # Third build, without --force. This should re-use the first build.
    sleep 1
    ch-image build -t force -f ./bucache/force.df ./bucache
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    blessed_out=$(cat << 'EOF'
*  WORKDIR /usr
*  RUN.F yum install -y ed         # doesn't need --force
| *  (force) WORKDIR /usr
| *  RUN yum install -y ed         # doesn't need --force
|/
*  WORKDIR /
*  (centos+7) PULL centos:7
*  (HEAD -> root) ROOT
EOF
)
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


### Additional test cases for correctness ###

@test "${tag}: reset" {
    # re-init
    run ch-image build-cache --reset
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'deleting build cache'* ]]
    [[ $output = *'initializing empty build cache'* ]]

    # fail if build cache disabled
    run ch-image build-cache --no-cache --reset
    [[ $status -eq 1 ]]
    echo "$output"
    [[ $output = *'build-cache subcommand invalid with build cache disabled'* ]]
}


@test "${tag}: gc" {
    ch-image build-cache --reset
    # Initial number of commits.
    diff -u <(  ch-image build-cache \
              | grep "commits" | awk '{print $2}') <(echo 1)

    # Number of commits after A.
    ch-image build -t a -f ./bucache/a.df .
    diff -u <(  ch-image build-cache \
              | grep "commits" | awk '{print $2}') <(echo 4)

    # Number of commits after 2x forced rebuilds of A (4 dangling)
    ch-image build --rebuild -t a -f ./bucache/a.df .
    ch-image build --rebuild -t a -f ./bucache/a.df .
    diff -u <(  ch-image build-cache \
              | grep "commits" | awk '{print $2}') <(echo 8)

    # Number of commits after garbage collecting.
    ch-image build-cache --gc
    diff -u <(  ch-image build-cache \
              | grep "commits" | awk '{print $2}') <(echo 4)
}

@test "${tag}: ARG and ENV" {
    ch-image build-cache --reset

    # Build.
    run ch-image build -t ae1 -f ./bucache/argenv.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1 vargA vargBvargA venvA venvBvargA'* ]]

    # Rebuild; this should hit and print the correct values.
    run ch-image build -t ae1 -f ./bucache/argenv.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'5* RUN'* ]]

    # Re-build, with partial hits. ARG and ENV from first build should pass
    # through with correct values.
    sleep 1
    run ch-image build -t ae2 -f ./bucache/argenv2.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'2 vargA vargBvargA venvA venvBvargA'* ]]

    # Re-build, setting ARG from the command line. This should miss.
    sleep 1
    run ch-image build --build-arg=argB=foo \
                       -t ae3 -f ./bucache/argenv.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"3. ARG argB='foo'"* ]]

    # Re-build, setting ARG from the command line to the same. Should hit.
    sleep 1
    run ch-image build --build-arg=argB=foo \
                       -t ae4 -f ./bucache/argenv.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"3* ARG argB='foo'"* ]]

    # Re-build, setting ARG from the command line to thing different. Miss.
    sleep 1
    run ch-image build --build-arg=argB=bar \
                       -t ae5 -f ./bucache/argenv.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"3. ARG argB='bar'"* ]]
    [[ $output = *'1 vargA bar venvA venvB'* ]]

    # Check for expected tree.
    run ch-image build-cache --tree --dot="${dot_base}argenv"
    echo "$output"
    [[ $status -eq 0 ]]
    blessed_out=$(cat << 'EOF'
*  (ae5) RUN echo 1 $argA $argB $envA $envB
*  ENV envB='venvBvargA'
*  ENV envA='venvA'
*  ARG argB='bar'
| *  (ae4, ae3) RUN echo 1 $argA $argB $envA $envB
| *  ENV envB='venvBvargA'
| *  ENV envA='venvA'
| *  ARG argB='foo'
|/
| *  (ae2) RUN echo 2 $argA $argB $envA $envB
| | *  (ae1) RUN echo 1 $argA $argB $envA $envB
| |/
| *  ENV envB='venvBvargA'
| *  ENV envA='venvA'
| *  ARG argB='vargBvargA'
|/
*  ARG argA='vargA'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: ARG special variables" {
    ch-image build-cache --reset
    unset SSH_AUTH_SOCK

    # Build. Should miss.
    run ch-image build -t foo -f ./bucache/argenv-special.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1. FROM'* ]]
    [[ $output = *'2. ARG'* ]]
    [[ $output = *'3. ARG'* ]]
    [[ $output = *'4. RUN'* ]]
    [[ $output = *'vargA sockA'* ]]

    # Re-build. All hits.
    run ch-image build -t foo -f ./bucache/argenv-special.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM'* ]]
    [[ $output = *'2* ARG'* ]]
    [[ $output = *'3* ARG'* ]]
    [[ $output = *'4* RUN'* ]]
    [[ $output != *'vargA sockA'* ]]

    # Re-build with new value from command line. All hits again.
    run ch-image build --build-arg=SSH_AUTH_SOCK=sockB \
                       -t foo -f ./bucache/argenv-special.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM'* ]]
    [[ $output = *'2* ARG'* ]]
    [[ $output = *'3* ARG'* ]]
    [[ $output = *'4* RUN'* ]]
    [[ $output != *'vargA sockA'* ]]
    [[ $output != *'vargA sockB'* ]]
}


@test "${tag}: COPY" {
    ch-image build-cache --reset

    # Prepare fixtures. These need various manipulating during the test, which
    # is why they're built here on the fly.
    fixtures=${BATS_TMPDIR}/copy-cache
    mkdir -p "$fixtures"
    echo hello > "$fixtures"/file1
    rm -f "$fixtures"/file1a
    mkdir -p "$fixtures"/dir1
    touch "$fixtures"/dir1/file1 "$fixtures"/dir1/file2

    printf '\n*** Build; all misses.\n\n'
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'. FROM'* ]]
    [[ $output = *'. COPY'* ]]

    printf '\n*** Re-build; all hits.\n\n'
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'* COPY'* ]]

    printf '\n*** Add remove file in directory; should miss b/c dir mtime.\n\n'
    touch "$fixtures"/dir1/file2
    rm "$fixtures"/dir1/file2
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'. COPY'* ]]

    printf '\n*** Re-build; all hits.\n\n'
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'* COPY'* ]]

    printf '\n*** Touch file; should miss because file mtime.\n\n'
    touch "$fixtures"/file1
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'. COPY'* ]]

    printf '\n*** Re-build; all hits.\n\n'
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'* COPY'* ]]

    printf '\n*** Rename file; should miss because filename.\n\n'
    mv "$fixtures"/file1 "$fixtures"/file1a
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'. COPY'* ]]

    printf '\n*** Re-build; all hits.\n\n'
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'* COPY'* ]]

    printf '\n*** Rename file back; still miss b/c ctime.\n\n'
    stat "$fixtures"/file1a
    mv "$fixtures"/file1a "$fixtures"/file1
    stat "$fixtures"/file1
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'. COPY'* ]]

    printf '\n*** Re-build; all hits.\n\n'
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'* COPY'* ]]

    printf '\n*** Update content, same length, reset mtime; miss b/c ctime.\n\n'
    cat "$fixtures"/file1
    stat "$fixtures"/file1
    mtime=$(stat -c %y "$fixtures"/file1)
    echo world > "$fixtures"/file1
    touch -d "$mtime" "$fixtures"/file1
    cat "$fixtures"/file1
    stat "$fixtures"/file1
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'. COPY'* ]]

    printf '\n*** Re-build; all hits.\n\n'
    run ch-image build -t foo -f ./bucache/copy.df "$fixtures"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'* COPY'* ]]
}


@test "${tag}: FROM non-cached base image" {
    ch-image build-cache --reset

    # Pull base image w/o cache.
    ch-image pull --no-cache alpine:3.9
    [[ ! -e $CH_IMAGE_STORAGE/img/alpine+3.9/.git ]]

    # Build child image.
    run ch-image build -t foo - <<'EOF'
FROM alpine:3.9
RUN echo foo
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'. FROM'* ]]
    [[ $output = *'base image only exists non-cached; adding to cache'* ]]
    [[ $output = *'. RUN'* ]]

    # Check tree.
    blessed_out=$(cat << 'EOF'
*  (foo) RUN echo foo
*  (alpine+3.9) IMPORT alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: all hits, new name" {
    ch-image build-cache --reset

    blessed_out=$(cat << 'EOF'
*  (a2, a) RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    ch-image build -t a -f ./bucache/a.df .
    ch-image build -t a2 -f ./bucache/a.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}


@test "${tag}: pull to default destination" {
    ch-image build-cache --reset

    printf '\n*** Case 1: Not in build cache\n\n'
    run ch-image pull alpine:3.9
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'pulling image:    alpine:3.9'* ]]
    [[ $output  = *'pulled image: adding to build cache'* ]]  # C1, C4
    [[ $output != *'pulled image: found in build cache'* ]]   # C2, C3

    printf '\n*** Case 2: In build cache, up to date\n\n'
    run ch-image pull alpine:3.9
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'pulling image:    alpine:3.9'* ]]
    [[ $output != *'pulled image: adding to build cache'* ]]  # C1, C4
    [[ $output  = *'pulled image: found in build cache'* ]]   # C2, C3

    printf '\n*** Case 3: In build cache, not UTD, UTD commit present\n\n'
    printf 'FROM alpine:3.9\n' | ch-image build -t foo -
    printf 'FROM foo\nRUN echo foo\n' | ch-image build -t alpine:3.9 -
    blessed_out=$(cat << 'EOF'
*  (alpine+3.9) RUN echo foo
*  (foo) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
    sleep 1
    run ch-image pull alpine:3.9
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'pulling image:    alpine:3.9'* ]]
    [[ $output != *'pulled image: adding to build cache'* ]]  # C1, C4
    [[ $output  = *'pulled image: found in build cache'* ]]   # C2, C3
    blessed_out=$(cat << 'EOF'
*  RUN echo foo
*  (foo, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    printf '\n*** Case 4: In build cache, not UTD, UTD commit absent\n\n'
    sleep 1
    printf 'FROM alpine:3.9\n' | ch-image build -t alpine:3.10 -
    blessed_out=$(cat << 'EOF'
*  RUN echo foo
*  (foo, alpine+3.9, alpine+3.10) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
    run ch-image pull alpine:3.10
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'pulling image:    alpine:3.10'* ]]
    [[ $output  = *'pulled image: adding to build cache'* ]]  # C1, C4
    [[ $output != *'pulled image: found in build cache'* ]]   # C2, C3
    blessed_out=$(cat << 'EOF'
*  (alpine+3.10) PULL alpine:3.10
| *  RUN echo foo
| *  (foo, alpine+3.9) PULL alpine:3.9
|/
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}: multistage COPY" {
    # Multi-stage build with no instructions in the first stage.
    df_no=$(cat <<'EOF'
FROM alpine:3.9
FROM alpine:3.10
COPY --from=0 /etc/os-release /
EOF
           )
    # Multi-stage build with instruction in the first stage.
    df_yes=$(cat <<'EOF'
FROM alpine:3.9
RUN echo foo
FROM alpine:3.10
COPY --from=0 /etc/os-release /
EOF
            )

    ch-image build-cache --reset
    echo "$df_no" | ch-image build -t tmpimg -f - .  # cold
    echo "$df_no" | ch-image build -t tmpimg -f - .  # hot

    ch-image build-cache --reset
    echo "$df_yes" | ch-image build -t tmpimg -f - .  # cold
    echo "$df_yes" | ch-image build -t tmpimg -f - .  # hot
}

@test "${tag}: pull to specified destination" {
    ch-image reset

    # pull special image to weird destination
    ch-image pull scratch foo

    # pull normal image to weird destination
    sleep 1
    ch-image pull alpine:3.9 bar

    # everything in order?
    blessed_tree=$(cat << 'EOF'
*  (bar, alpine+3.9) PULL alpine:3.9
| *  (scratch, foo) PULL scratch
|/
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
    ls -x "$CH_IMAGE_STORAGE"/img
    [[ $(ls -x "$CH_IMAGE_STORAGE"/img) == "bar  foo" ]]

    # pull same normal image normally
    sleep 1
    ch-image pull alpine:3.9

    # everything still in order?
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
    ls -x "$CH_IMAGE_STORAGE"/img
    [[ $(ls -x "$CH_IMAGE_STORAGE"/img) == "alpine+3.9  bar  foo" ]]
}


@test "${tag}: §3.6 rebuild" {
    ch-image build-cache --reset

    # Build. Mode should not matter here, but we use enabled because that's
    # more lifelike.
    ch-image build -t a -f ./bucache/a.df ./bucache

    # Re-build in "rebuild" mode. FROM should hit, others miss, and we should
    # have two branches.
    sleep 1
    run ch-image build --rebuild -t a -f ./bucache/a.df ./bucache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'* FROM'* ]]
    [[ $output = *'. RUN echo foo'* ]]
    [[ $output = *'. RUN echo bar'* ]]
    blessed_out=$(cat << 'EOF'
*  (a) RUN echo bar
*  RUN echo foo
| *  RUN echo bar
| *  RUN echo foo
|/
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) ROOT
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}rebuild"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # Re-build again in "rebuild" mode. The branch pointer should move to the
    # newer execution.
    run ch-image build-cache -v --tree
    echo "$output"
    [[ $status -eq 0 ]]
    commit_before=$(echo "$output" | sed -En 's/^.+\(a\) ([0-9a-f]+).+$/\1/p')
    echo "before: ${commit_before}"
    sleep 1
    ch-image build --rebuild -t a -f ./bucache/a.df ./bucache
    run ch-image build-cache -v --tree
    echo "$output"
    [[ $status -eq 0 ]]
    commit_after=$(echo "$output" | sed -En 's/^.+\(a\) ([0-9a-f]+).+$/\1/p')
    echo "after: ${commit_after}"
    [[ $commit_before != "$commit_after" ]]
}


@test "${tag}: empty dir persistence" {
    ch-image build-cache --reset
    ch-image delete tmpimg || true

    ch-image build -t tmpimg - <<'EOF'
FROM alpine:3.9
RUN mkdir /foo && mkdir /foo/bar
EOF
    sleep 1
    ch-image build -t tmpimg - <<'EOF'
FROM alpine:3.9
RUN true        # miss
RUN mkdir /foo  # should not collide with leftover /foo from above
EOF
}


@test "${tag}: garbage vs. reset" {
    rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

    # Init build cache.
    ch-image list
    cd "$CH_IMAGE_STORAGE"/bucache

    # Turn off auto-gc so it's not triggered during the build itself.
    git config gc.auto 0

    # Build an image that’s going to be annoying to garbage collect, but not
    # too annoying, so the test isn’t too long. Keep in mind this is probably
    # happening on a tmpfs.
    ch-image build -t tmpimg - <<'EOF'
FROM alpine:3.9
RUN for i in $(seq 0 1024); do \
       dd if=/dev/urandom of=/$i bs=192K count=1 status=none; \
    done
EOF

    # Turn auto-gc back on, and configure it to run basically always.
    git config gc.auto 1
    #git config gc.autoDetach false  # for testing
    cat config

    # Garbage collect. Use raw Git commands so we can control exactly what is
    # going on.
    git gc --auto

    # Reset the cache while garbage collection is still running.
    cd ..
    run ch-image build-cache --reset
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'stopping build cache garbage collection'* ]]
}
