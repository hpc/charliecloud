load ../common

# shellcheck disable=SC2034
tag='ch-image --force'

setup () {
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
}

@test "${tag}: no matching distro" {
    scope standard

    # without --force
    run ch-image -v build -t tmpimg -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'--force not available (no suitable config found)'* ]]

    # with --force
    run ch-image -v build --force -t tmpimg -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'--force not available (no suitable config found)'* ]]
}

@test "${tag}: --no-force-detect" {
    scope standard

    run ch-image -v build --no-force-detect -t tmpimg -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'not detecting --force config, per --no-force-detect'* ]]
}

@test "${tag}: misc errors" {
    scope standard

    run ch-image build --force --no-force-detect .
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = 'error'*'are incompatible'* ]]
}

@test "${tag}: multiple RUN" {
    scope standard

    # 1. List form of RUN.
    # 2. apt-get not at beginning.
    run ch-image -v build --force -t tmpimg -f - . <<'EOF'
FROM debian:buster
RUN true
RUN true && apt-get update
RUN ["apt-get", "install", "-y", "hello"]
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -Fc 'init step 1: checking: $') -eq 1 ]]
    [[ $(echo "$output" | grep -Fc 'init step 1: $') -eq 1 ]]
    [[ $(echo "$output" | grep -Fc 'RUN: new command:') -eq 2 ]]
    [[ $output = *'init: already initialized'* ]]
    [[ $output = *'--force: init OK & modified 2 RUN instructions'* ]]
    [[ $output = *'grown in 4 instructions: tmpimg'* ]]
}
