load ../common

# shellcheck disable=SC2034
tag='ch-grow --force'

setup () {
    [[ $CH_BUILDER = ch-grow ]] || skip 'ch-grow only'
}

@test "${tag}: no matching distro" {
    scope standard

    # without --force
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'--force not available (no suitable config found)'* ]]

    # with --force
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'--force not available (no suitable config found)'* ]]
}

@test "${tag}: --no-force-detect" {
    scope standard

    run ch-grow -v build --no-force-detect -t fakeroot-temp -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'not detecting --force config, per --no-force-detect'* ]]

}

@test "${tag}: misc errors" {
    scope standard

    run ch-grow build --force --no-force-detect .
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = 'error'*'are incompatible'* ]]
}

@test "${tag}: multiple RUN" {
    scope standard

    # 1. List form of RUN.
    # 2. apt-get not at beginning.
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
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
    [[ $output = *'grown in 4 instructions: fakeroot-temp'* ]]
}

@test "${tag}: CentOS 7" {
    scope full

    # no commands that may need it, without --force, build succeeds
    # also: correct config, last config tested is the one selected
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: rhel7'* ]]
    [[ $output = *$'testing config: rhel7\navailable --force'* ]]

    # no commands that may need it, without --force, build fails
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]

    # no commands that may need it, with --force, warning
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]

    # commands that may need it, but turns out they don’t, without --force
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN yum install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]

    # commands that may need it, but turns out they don’t, with --force
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN yum install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]

    # commands that may need it, they do, fail & suggest
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN yum install -y openssh
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]

    # commands that may need it, they do, --force, success
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN yum install -y openssh
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: CentOS 8" {
    scope standard

    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: rhel8'* ]]

    # no commands that may need it, without --force, build fails
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]

    # no commands that may need it, with --force, warning
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]

    # commands that may need it, but turns out they don’t, without --force
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN dnf install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]

    # commands that may need it, but turns out they don’t, with --force
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN dnf install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]

    # commands that may need it, they do, fail & suggest
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]

    # commands that may need it, they do, --force, success
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Debian Stretch" {
    scope full

    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: debSB'* ]]

    # no commands that may need it, without --force, build fails
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]

    # no commands that may need it, with --force, warning
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]

    # commands that may need it, but turns out they don’t, without --force
    #
    # FIXME: Not sure how to do this on Debian; any use of apt-get to install
    # needs "apt-get update" first, which requires --force.

    # commands that may need it, but turns out they don’t, with --force
    #
    # FIXME: Not sure how to do this on Debian; any use of apt-get to install
    # needs "apt-get update" first, which requires --force.

    # commands that may need it, they do, fail & suggest
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]

    # commands that may need it, they do, --force, success
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Debian Buster" {
    scope full

    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: debSB'* ]]

    # no commands that may need it, without --force, build fails
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]

    # no commands that may need it, with --force, warning
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]

    # commands that may need it, but turns out they don’t, without --force
    #
    # FIXME: Not sure how to do this on Debian; any use of apt-get to install
    # needs "apt-get update" first, which requires --force.

    # commands that may need it, but turns out they don’t, with --force
    #
    # FIXME: Not sure how to do this on Debian; any use of apt-get to install
    # needs "apt-get update" first, which requires --force.

    # commands that may need it, they do, fail & suggest
    run ch-grow -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]

    # commands that may need it, they do, --force, success
    run ch-grow -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}
