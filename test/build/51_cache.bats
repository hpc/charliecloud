load ../common

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
}

@test 'build-cache initial state' {
    run ch-image reset
    [[ $status -eq 0 ]]

    blessed_out=$(cat << 'EOF'
*  (HEAD -> root) 
EOF
)
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    diff -u <(echo "$output") <(echo "$blessed_out")
}

@test 'build-cache pull state' {
    blessed_out=$(cat << 'EOF'
*  (alpine+latest) FROM alpine+latest
| 
*  (HEAD -> root) 
EOF
)
    ch-image pull alpine:latest
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    diff -u <(echo "$output") <(echo "$blessed_out")
}

@test 'build-cache example A' {
    blessed_out=$(cat << 'EOF'
*  (img_a) RUN echo bar
| 
*  RUN echo foo
| 
*  (alpine+latest) FROM alpine+latest
| 
*  (HEAD -> root) 
EOF
)
    ch-image build -t img_a -f - . <<'EOF'
FROM alpine:latest
RUN echo foo
RUN echo bar
EOF
    run ch-image build-cache --tree-text
    [[ $status -eq 0 ]]
    diff -u <(echo "$output") <(echo "$blessed_out")
}

@test 'build-cache example B' {
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

@test 'build-cache example C' {
    # 
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
