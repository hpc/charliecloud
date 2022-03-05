load ../common

# shellcheck disable=SC2034
tag=bucache

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

version_check () {
    cmd=$1
    min=$2
    ver=$3
    if [[ $(  printf '%s\n%s\n' "$min" "$ver" \
            | sort -V | head -n1) != "$min" ]]; then
        pedantic_fail "$cmd '$ver' < $min"
    fi
}

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
    [[ $CH_BUCACHE_MODE == "disabled" ]] && skip "developer disabled"
    # Use a separate storage directory so we don't mess up the main one.
    export CH_IMAGE_STORAGE=$BATS_TMPDIR/butest
    dot_base=$BATS_TMPDIR/bu_
    if [[ -z $git_version ]]; then
        pedantic_fail "git not in path"
    fi
    version_check 'git' '2.28.1' "$git_version"
    [[ $(command -v git2dot.py) ]] || pedantic_fail 'git2dot.py not in path'
    version_check 'git2dot.py' '0.8.3' <(git2dot.py -V | awk '{print $3}')
    [[ $(command -v dot) ]] || pedantic_fail 'dot not in path'
    # FIXME: use regex
    version_check 'dot' '2.30.1' <(dot -V | awk '{print $5}')
}

@test "${tag}/§3.1 empty cache" {
    rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

    blessed_tree=$(cat << EOF
initializing storage directory: v3 ${CH_IMAGE_STORAGE}
initializing empty build cache
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}empty"
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

@test "${tag}/§3.2.1 initial pull" {
    ch-image pull alpine:3.9

    blessed_tree=$(cat << 'EOF'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}initial-pull"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}

@test "${tag}/§3.5 FROM" {
    # FROM pulls
    ch-image build-cache --reset
    run ch-image build -v -t d -f bucache/from.df .
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1. FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (d, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
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
*  (HEAD -> root) root
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
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}

@test "${tag}/§3.3.1 Dockerfile A" {
    ch-image build-cache --reset

    ch-image build -t a -f bucache/a.df .

    blessed_out=$(cat << 'EOF'
*  (a) RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}a"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.3.2 Dockerfile B" {
    ch-image build-cache --reset

    ch-image build -t a -f bucache/a.df .
    ch-image build -t b -f bucache/b.df .

    blessed_out=$(cat << 'EOF'
*  (b) RUN echo baz
*  (a) RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}b"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.3.3 Dockerfile C" {
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
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}c"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/rebuild A" {
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
*  (HEAD -> root) root
EOF
)
    ch-image --bucache=rebuild build -t a -f bucache/a.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    echo "$output"
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/rebuild B" {
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
*  (HEAD -> root) root
EOF
)
    ch-image --bucache=rebuild build -t b -f bucache/b.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/rebuild C" {
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
*  (HEAD -> root) root
EOF
)
    ch-image --bucache=rebuild build -t c -f bucache/c.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.7 change then revert" {
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
*  (HEAD -> root) root
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
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}revert2"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/gc" {
    ch-image build-cache --reset
    # Initial number of commits.
    diff -u <(  ch-image build-cache \
              | grep "commits" | awk '{print $2}') <(echo 1)

    # Number of commits after A.
    ch-image build -t a -f ./bucache/a.df .
    diff -u <(  ch-image build-cache \
              | grep "commits" | awk '{print $2}') <(echo 4)

    # Number of commits after 2x forced rebuilds of A (4 dangling)
    ch-image build --bucache=rebuild -t a -f ./bucache/a.df .
    ch-image build --bucache=rebuild -t a -f ./bucache/a.df .
    diff -u <(  ch-image build-cache \
              | grep "commits" | awk '{print $2}') <(echo 8)

    # Number of commits after garbage collecting.
    ch-image build-cache --gc
    diff -u <(  ch-image build-cache \
              | grep "commits" | awk '{print $2}') <(echo 4)
}

@test "${tag}/branch readiness" {
    ch-image build-cache --reset

    blessed_out=$(cat << 'EOF'
*  RUN echo bar
*  (a+NR) RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    # Build A, then introduce a failure to A's Dockerfile and build again.
    # The first instruction FOO hits; the the second instruction fails leaving
    # the A branch in a not ready state pointing to FOO.
    ch-image build -t a -f bucache/a.df .
    run ch-image build -t a -f ./bucache/a2.df .
    [[ $status -ne 0 ]]
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # Build original A again. Since no A instruction needs to be
    # re-executed (all hits) there are now two branches: a ready and not ready.
    blessed_out=$(cat << 'EOF'
*  (a) RUN echo bar
*  (a+NR) RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    ch-image build -t a -f ./bucache/a.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # Add new working instructions to A. Since we now have a miss, the not-ready
    # branch is replaced with a new not-ready branch (pointing to the last
    # successful parent commit of A), and marked ready when the build succeeds.
    # Thus there should be zero not-ready branches.
    blessed_out=$(cat << 'EOF'
*  (a) RUN echo wordle
*  RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    ch-image build -t a -f ./bucache/a3.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

}

@test "${tag}/ARG and ENV" {
    ch-image build-cache --reset

    # Ensure ARG and ENV work.
    blessed_out=$(cat << 'EOF'
*  (ae) RUN $env_
*  RUN $arg_
*  ENV env_='/bin/true'
*  ARG arg_='/bin/true'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    ch-image build -t ae -f ./bucache/ae.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # Same name. Miss. Ensure ARG and ENV hits still set their variables.
    blessed_out=$(cat << 'EOF'
*  (ae) RUN $arg && $env_
*  RUN $env_
*  RUN $arg_
*  ENV env_='/bin/true'
*  ARG arg_='/bin/true'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    ch-image build -t ae -f ./bucache/ae2.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/all hits, new name" {
    ch-image build-cache --reset

    blessed_out=$(cat << 'EOF'
*  (a2, a) RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    ch-image build -t a -f ./bucache/a.df .
    ch-image build -t a2 -f ./bucache/a.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/force" {
    ch-image build-cache --reset

    blessed_out=$(cat << 'EOF'
*  (yes_f) [force] RUN apt-get install -y git
*  [force] RUN apt-get -y upgrade
| *  (no_f+NR) RUN apt-get -y upgrade
|/
*  (debian) PULL debian
*  (HEAD -> root) root
EOF
)
    # Build debian image without force; both "apt-get update" and "install git"
    # fail without force. The asoociated branch is marked not ready.
    run ch-image build -t no_f -f ./bucache/force.df .
    [[ $status -ne 0 ]]
    # Build same image with different tag using force; this will succeed and
    # thus we should have two branches in the cache.
    ch-image build --force -t yes_f -f ./bucache/force.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.4.1 two pulls, same" {
    ch-image build-cache --reset
    ch-image pull alpine:3.9
    ch-image pull alpine:3.9

    blessed_out=$(cat << 'EOF'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.4.2 two pulls, different" {

    # We simulate a repository change by manually editing the skinny manifest in
    # local storage. This would occur in the wild as follows:
    #    1. pull alpine:3.9
    #    2. a change occurs to the image in the repository
    #    3. run pull --no-cache alpine:3.9
    # Now the existing SID of the image will differ from the SID in
    # the build-cache, resulting in a warning stating that the image is stale
    # and a fresh pull.
    ch-image build-cache --reset
    ch-image pull alpine:3.9
    sed -i 's/json/fson/' "${CH_IMAGE_STORAGE}/dlcache/alpine+3.9"*manifest.json
    run ch-image pull alpine:3.9
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output == *"warning: cached image stale; re-pulling"* ]]
}

@test "${tag}/WORKDIR" {
    ch-image build-cache --reset
    ch-image build -t wd1 -f ./bucache/workdir.df .

    # Same name. Miss. Last instruction is a cached hit WORKDIR.
    blessed_out=$(cat << 'EOF'
*  (wd1) RUN [[ -e ./foo ]]
| *  RUN pwd
|/
*  WORKDIR /wd
*  RUN touch wd/foo
*  RUN mkdir wd
*  (alpine+latest) PULL alpine:latest
*  (HEAD -> root) root
EOF
)
    ch-image build -t wd1 -f ./bucache/workdir2.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # New name. Miss. Last instruction is a cached hit WORKDIR.
    blessed_out=$(cat << 'EOF'
*  (wd2) RUN [[ -e ./foo ]] && [[ -e ./foo ]]
| *  (wd1) RUN [[ -e ./foo ]]
|/
| *  RUN pwd
|/
*  WORKDIR /wd
*  RUN touch wd/foo
*  RUN mkdir wd
*  (alpine+latest) PULL alpine:latest
*  (HEAD -> root) root
EOF
)
    ch-image build -t wd2 -f ./bucache/workdir3.df .
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}
