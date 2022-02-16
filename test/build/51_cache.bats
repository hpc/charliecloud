load ../common

tag=bucache

treeonly () {
    sed -E '/^$/Q'
}

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
    # Use a separate storage directory so we don't mess up the main one.
    export CH_IMAGE_STORAGE=$BATS_TMPDIR/butest
}

@test "${tag}/initial state" {
    rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

    blessed_tree=$(cat << EOF
initializing storage directory: v3 ${CH_IMAGE_STORAGE}
initializing empty build cache
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}

@test "${tag}/reset" {
    # re-init
    run ch-image build-cache --reset
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'deleting build cache'* ]]
    [[ $output = *'initializing empty build cache'* ]]

    # fail if build cache disabled
    run ch-image build-cache --bucache=disabled --reset
    [[ $status -eq 1 ]]
    echo "$output"
    [[ $output = *'build-cache subcommand invalid with build cache disabled'* ]]
}

@test "${tag}/pull" {
    ch-image pull alpine:3.9

    blessed_tree=$(cat << 'EOF'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}

@test "${tag}/FROM" {
    # FROM pulls
    ch-image build-cache --reset
    run ch-image build -v -t from1 -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1. FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (from1, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)

    # FROM doesn't pull (same target name)
    run ch-image build -v -t from1 -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (from1, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)

    # FROM doesn't pull (different target name)
    run ch-image build -v -t from2 -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (from2, from1, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}

@test "${tag}/build A" {
    ch-image build -t img_a -f - . <<'EOF'
FROM alpine:3.9
RUN echo foo
RUN echo bar
EOF

    blessed_out=$(cat << 'EOF'
*  (img_a) RUN ["/bin/sh", "-c", "echo bar"]
*  RUN ["/bin/sh", "-c", "echo foo"]
*  (from2, from1, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test 'build cache B' {
    skip
    # image B state, i.e., a1, b2, c3, d4, and e5 commits
    blessed_out=$(cat << 'EOF'
*  (img_b) RUN echo baz
| 
*  (img_a) RUN echo bar
| 
*  RUN echo foo
| 
*  (alpine+latest) FROM alpine+latest
| 
*  (HEAD -> root)
EOF
)
    ch-image build -t img_b -f - . <<'EOF'
FROM img_a
RUN echo baz
EOF
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    diff -u <(echo "$output") <(echo "$blessed_out")
}

@test 'build cache C' {
    skip
    blessed_out=$(cat << 'EOF'
*  (img_c) RUN echo qux
| 
| *  (img_b) RUN echo baz
| | 
| *  (img_a) RUN echo bar
|/  
|   
*  RUN echo foo
| 
*  (alpine+latest) FROM alpine+latest
| 
*  (HEAD -> root)
EOF
)
    ch-image build -t img_c -f - . <<'EOF'
FROM alpine:latest
RUN echo foo
RUN echo qux
EOF
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    diff -u <(echo "$output") <(echo "$blessed_out")
}

@test 'build cache rebuild A' {
    skip
    # Forcing a rebuild show produce a new pair of FOO and BAR commits from
    # from the alpine branch.
    blessed_out=$(cat << 'EOF'
*  (img_a) RUN echo bar
| 
*  RUN echo foo
| 
| *  (img_c) RUN echo qux
| | 
| | *  (img_b) RUN echo baz
| | | 
| | *  RUN echo bar
| |/  
| |   
| *  RUN echo foo
|/  
|   
*  (alpine+latest) FROM alpine+latest
| 
*  (HEAD -> root)
EOF
)
    ch-image --build-cache=rebuild build -t img_a -f - . <<'EOF'
FROM alpine:latest
RUN echo foo
RUN echo bar
EOF
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    diff -u <(echo "$output") <(echo "$blessed_out")

}

@test 'build cache rebuild B' {
    skip
    # Rebuild of B. Since img_a was rebuilt in the last test, and because
    # the rebuild behavior only forces misses on non-FROM instructions, it
    # should now be based on img_a's new commits.
    blessed_out=$(cat << 'EOF'
*  (img_b) RUN echo baz
| 
*  (img_a) RUN echo bar
| 
*  RUN echo foo
| 
| *  (img_c) RUN echo qux
| | 
| *  RUN echo foo
|/  
|   
*  (alpine+latest) FROM alpine+latest
| 
*  (HEAD -> root)
EOF
)
    ch-image --build-cache=rebuild build -t img_b -f - . <<'EOF'
FROM img_a
RUN echo baz
EOF
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    diff -u <(echo "$output") <(echo "$blessed_out")
}

@test 'build cache rebuild C' {
    skip
    # Rebuild C. Since C doesn't reference img_a (like img_b does) rebuilding
    # causes a miss on FOO. Thus C makes new FOO and QUX commits.
    blessed_out=$(cat << 'EOF'
*  (img_c) RUN echo qux
| 
*  RUN echo foo
| 
| *  (img_b) RUN echo baz
| | 
| *  (img_a) RUN echo bar
| | 
| *  RUN echo foo
|/  
|   
*  (alpine+latest) FROM alpine+latest
| 
*  (HEAD -> root)
EOF
)
    ch-image --build-cache=rebuild build -t img_c -f - . <<'EOF'
FROM alpine:latest
RUN echo foo
RUN echo qux
EOF
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    diff -u <(echo "$output") <(echo "$blessed_out")
}

# needed tests:
# --gc
# --dot
# various difficult files (see git_prepare)
# pull twice in row (should replace directory in img)
# all hits, new name
# multi-stage build
