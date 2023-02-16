load ../common

# shellcheck disable=SC2034
tag='ch-image --force'

setup () {
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
    export CH_IMAGE_CACHE=disabled
}

@test "${tag}: no matching distro" {
    scope standard

    # without --force
    run ch-image -v build --no-cache -t tmpimg -f - . <<'EOF'
FROM hello-world:latest
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'--force not available (no suitable config found)'* ]]

    # with --force
    run ch-image -v build --force -t tmpimg -f - . <<'EOF'
FROM hello-world:latest
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'--force not available (no suitable config found)'* ]]
}

@test "${tag}: --no-force-detect" {
    scope standard

    run ch-image -v build --no-force-detect -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
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

@test "${tag}: dpkg(8)" {
    # Typically folks will use apt-get(8), but bare dpkg(8) also happens.
    scope standard
    [[ $(uname -m) = x86_64 ]] || skip 'amd64 only'

    # NOTE: This produces a broken system because we ignore openssh-client’s
    # dependencies, but it’s good enough to test --force.
    ch-image -v build --rebuild --force -t tmpimg -f - . <<'EOF'
FROM debian:buster
RUN apt-get update && apt install -y wget
RUN wget -nv https://snapshot.debian.org/archive/debian/20230213T151507Z/pool/main/o/openssh/openssh-client_8.4p1-5%2Bdeb11u1_amd64.deb
RUN dpkg --install --force-depends *.deb
EOF
}

@test "${tag}: rpm(8)" {
    # Typically folks will use yum(8) or dnf(8), but bare rpm(8) also happens.
    scope standard
    [[ $(uname -m) = x86_64 ]] || skil 'amd64 only'

    ch-image -v build --rebuild --force -t tmpimg -f - . <<'EOF'
FROM almalinux:8
RUN curl -sO https://repo.almalinux.org/vault/8.6/BaseOS/x86_64/os/Packages/openssh-8.0p1-13.el8.x86_64.rpm
RUN rpm --install *.rpm
EOF
}

@test "${tag}: list form" {
    scope standard

    ch-image -v build --rebuild --force -t tmpimg -f - . <<'EOF'
FROM debian:buster
RUN ["apt-get", "update"]
RUN ["apt-get", "install", "-y", "openssh-client"]
EOF
}
