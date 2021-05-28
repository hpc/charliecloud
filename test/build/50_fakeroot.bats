load ../common

# shellcheck disable=SC2034
tag='ch-image --force'

setup () {
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
}

@test "${tag}: no matching distro" {
    scope standard

    # without --force
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'--force not available (no suitable config found)'* ]]

    # with --force
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM alpine:3.9
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'--force not available (no suitable config found)'* ]]
}

@test "${tag}: --no-force-detect" {
    scope standard

    run ch-image -v build --no-force-detect -t fakeroot-temp -f - . <<'EOF'
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
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
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

@test "${tag}: CentOS 7: unneeded, no --force, build succeeds" {
    scope standard
    # no commands that may need it, without --force, build succeeds
    # also: correct config, last config tested is the one selected
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: rhel7'* ]]
    [[ $output = *$'testing config: rhel7\navailable --force'* ]]
}

@test "${tag}: CentOS 7: unneeded, no --force, build fails" {
    scope full
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: CentOS 7: unneeded, with --force" {
    scope full
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

@test "${tag}: CentOS 7: maybe needed but actually not, no --force" {
    scope full
    # commands that may need it, but turns out they don’t, without --force
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN yum install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
}

@test "${tag}: CentOS 7: maybe needed but actually not, with --force" {
    scope full
    # commands that may need it, but turns out they don’t, with --force
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN yum install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: CentOS 7: needed but no --force" {
    scope full
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN yum install -y openssh
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: CentOS 7: needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:7
RUN yum install -y openssh
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: CentOS 7: EPEL already installed" {
    scope standard

    # 7: install EPEL (no fakeroot)
    run ch-image -v build -t centos7-epel1 -f - . <<'EOF'
FROM centos:7
RUN yum install -y epel-release
RUN yum repolist -v | egrep '^Repo-id\s+: epel/'
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force'* ]]
    echo "$output" | grep -E 'Installing.+: epel-release'

    # 7: install openssh (with fakeroot)
    run ch-image -v build --force -t centos7-epel2 -f - . <<'EOF'
FROM centos7-epel1
RUN yum install -y openssh
RUN yum repolist -v | egrep '^Repo-id\s+: epel/'
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 2 RUN instructions'* ]]
    ! ( echo "$output" | grep -E '(Updating|Installing).+: epel-release' )
}

@test "${tag}: CentOS 8: unneeded, no --force, build succeeds" {
    scope standard
    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: rhel8'* ]]
}

@test "${tag}: CentOS 8: unneeded, no --force, build fails" {
    scope standard
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: CentOS 8: unneeded, with --force" {
    scope standard
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

@test "${tag}: CentOS 8: maybe needed but actually not, no --force" {
    scope standard
    # commands that may need it, but turns out they don’t, without --force
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN dnf install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
}

@test "${tag}: CentOS 8: maybe needed but actually not, with --force" {
    scope standard
    # commands that may need it, but turns out they don’t, with --force
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN dnf install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: CentOS 8: needed but no --force" {
    scope standard
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: CentOS 8: needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM centos:8
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
    # validate EPEL has been removed
    ! ls -lh "$CH_IMAGE_STORAGE"/img/fakeroot-temp/etc/yum.repos.d/epel*.repo
}

@test "${tag}: CentOS 8: EPEL already installed" {
    scope standard

    # install EPEL, no --force
    run ch-image -v build -t epel1 -f - . <<'EOF'
FROM centos:8
RUN dnf install -y epel-release
RUN dnf repolist | egrep '^epel'
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force'* ]]
    echo "$output" | grep -E 'Installing.+: epel-release'

    # new image based on that
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM epel1
RUN dnf install -y openssh
RUN dnf repolist | egrep '^epel'
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 2 RUN instructions'* ]]
    ! ( echo "$output" | grep -E '(Updating|Installing).+: epel-release' )
    # validate EPEL is installed *and* enabled
    ls -lh "$CH_IMAGE_STORAGE"/img/fakeroot-temp/etc/yum.repos.d/epel*.repo
    grep -Eq 'enabled=1' "$CH_IMAGE_STORAGE"/img/fakeroot-temp/etc/yum.repos.d/epel*.repo
}

@test "${tag}: RHEL UBI 8: needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM registry.access.redhat.com/ubi8/ubi
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
    # validate EPEL has been removed
    ! ls -lh "$CH_IMAGE_STORAGE"/img/fakeroot-temp/etc/yum.repos.d/epel*.repo
}

@test "${tag}: Debian Stretch: unneeded, no --force, build succeeds" {
    scope standard
    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: debderiv'* ]]
}

@test "${tag}: Debian Stretch: unneeded, no --force, build fails" {
    scope full
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Debian Stretch: unneeded, with --force" {
    scope full
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

# FIXME: Not sure how to do this on Debian; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Debian Stretch: maybe needed but actually not, no --force" {
#}

# FIXME: Not sure how to do this on Debian; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Debian Stretch: maybe needed but actually not, with --force" {
#}

@test "${tag}: Debian Stretch: needed but no --force" {
    scope full
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Debian Stretch: needed, with --force" {
    scope full
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM debian:stretch
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Debian Buster: unneeded, no --force, build succeeds" {
    scope standard
    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: debderiv'* ]]
}

@test "${tag}: Debian Buster: unneeded, no --force, build fails" {
    scope full
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Debian Buster: unneeded, with --force" {
    scope full
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

# FIXME: Not sure how to do this on Debian; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Debian Stretch: maybe needed but actually not, no --force" {
#}

# FIXME: Not sure how to do this on Debian; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Debian Stretch: maybe needed but actually not, with --force" {
#}

@test "${tag}: Debian Buster: needed but no --force" {
    scope full
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Debian Buster: needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM debian:buster
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Ubuntu 16 (Xenial): unneeded, no --force, build succeeds" {
    scope full
    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:xenial
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: debderiv'* ]]
}

@test "${tag}: Ubuntu 16 (Xenial): unneeded, no --force, build fails" {
    scope full
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:xenial
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Ubuntu 16 (Xenial): unneeded, with --force" {
    scope full
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:xenial
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

# FIXME: Not sure how to do this on Ubuntu; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Ubuntu 16 (Xenial): maybe needed but actually not, no --force" {
#}

# FIXME: Not sure how to do this on Ubuntu; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Ubuntu 16 (Xenial): maybe needed but actually not, with --force" {
#}

@test "${tag}: Ubuntu 16 (Xenial): needed but no --force" {
    scope full
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:xenial
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Ubuntu 16 (Xenial): needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:xenial
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Ubuntu 18 (Bionic): unneeded, no --force, build succeeds" {
    scope full
    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:bionic
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: debderiv'* ]]
}

@test "${tag}: Ubuntu 18 (Bionic): unneeded, no --force, build fails" {
    scope full
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:bionic
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Ubuntu 18 (Bionic): unneeded, with --force" {
    scope full
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:bionic
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

# FIXME: Not sure how to do this on Ubuntu; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Ubuntu 18 (Bionic): maybe needed but actually not, no --force" {
#}

# FIXME: Not sure how to do this on Ubuntu; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Ubuntu 18 (Bionic): maybe needed but actually not, with --force" {
#}

@test "${tag}: Ubuntu 18 (Bionic): needed but no --force" {
    scope full
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:bionic
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Ubuntu 18 (Bionic): needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:bionic
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Ubuntu 20 (Focal): unneeded, no --force, build succeeds" {
    scope full
    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:focal
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: debderiv'* ]]
}

@test "${tag}: Ubuntu 20 (Focal): unneeded, no --force, build fails" {
    scope full
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:focal
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Ubuntu 20 (Focal): unneeded, with --force" {
    scope full
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:focal
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

# FIXME: Not sure how to do this on Ubuntu; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Ubuntu 20 (Focal): maybe needed but actually not, no --force" {
#}

# FIXME: Not sure how to do this on Ubuntu; any use of apt-get to install
# needs "apt-get update" first, which requires --force.
#@test "${tag}: Ubuntu 20 (Focal): maybe needed but actually not, with --force" {
#}

@test "${tag}: Ubuntu 20 (Focal): needed but no --force" {
    scope full
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:focal
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Ubuntu 20 (Focal): needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM ubuntu:focal
RUN apt-get update && apt-get install -y openssh-client
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Fedora 26: unneeded, no --force, build succeeds" {
    scope standard
    # We would prefer to test the lowest supported --force version, 24,
    # but the ancient version of dnf it has doesn't fail the transaction when
    # a package fails so we test with 26 instead.
    #
    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM fedora:26
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: fedora'* ]]
}

@test "${tag}: Fedora 26: unneeded, no --force, build fails" {
    scope full
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM fedora:26
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Fedora 26: unneeded, with --force" {
    scope full
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM fedora:26
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

@test "${tag}: Fedora 26: maybe needed but actually not, no --force" {
    scope full
    # commands that may need it, but turns out they don’t, without --force
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM fedora:26
RUN dnf install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
}

@test "${tag}: Fedora 26: maybe needed but actually not, with --force" {
    scope full
    # commands that may need it, but turns out they don’t, with --force
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM fedora:26
RUN dnf install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Fedora 26: needed but no --force" {
    scope full
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM fedora:26
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Fedora 26: needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM fedora:26
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Fedora latest: unneeded, no --force, build succeeds" {
    scope standard
    # no commands that may need it, without --force, build succeeds
    # also: correct config
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM fedora:latest
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force: fedora'* ]]
}

@test "${tag}: Fedora latest: unneeded, no --force, build fails" {
    scope standard
    # no commands that may need it, without --force, build fails
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM fedora:latest
RUN false
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"build failed: current version of --force wouldn't help"* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Fedora latest: unneeded, with --force" {
    scope standard
    # no commands that may need it, with --force, warning
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM fedora:latest
RUN true
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: --force specified, but nothing to do'* ]]
}

@test "${tag}: Fedora latest: maybe needed but actually not, no --force" {
    scope standard
    # commands that may need it, but turns out they don’t, without --force
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM fedora:latest
RUN dnf install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
}

@test "${tag}: Fedora latest: maybe needed but actually not, with --force" {
    scope standard
    # commands that may need it, but turns out they don’t, with --force
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM fedora:latest
RUN dnf install -y ed
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}

@test "${tag}: Fedora latest: needed but no --force" {
    scope standard
    # commands that may need it, they do, fail & suggest
    run ch-image -v build -t fakeroot-temp -f - . <<'EOF'
FROM fedora:latest
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'available --force'* ]]
    [[ $output = *'RUN: available here with --force'* ]]
    [[ $output = *'build failed: --force may fix it'* ]]
    [[ $output = *'build failed: RUN command exited with 1'* ]]
}

@test "${tag}: Fedora latest: needed, with --force" {
    scope standard
    # commands that may need it, they do, --force, success
    run ch-image -v build --force -t fakeroot-temp -f - . <<'EOF'
FROM fedora:latest
RUN dnf install -y --setopt=install_weak_deps=false openssh
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'will use --force'* ]]
    [[ $output = *'--force: init OK & modified 1 RUN instructions'* ]]
}