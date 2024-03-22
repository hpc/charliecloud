load ../common

setup () {
    [[ $CH_TEST_PACK_FMT = *-unpack ]] || skip 'need writeable image'
    [[ $CHTEST_GITWD ]] || skip "not in Git working directory"
    if     ! command -v sphinx-build > /dev/null 2>&1 \
        && ! command -v sphinx-build-3.6 > /dev/null 2>&1; then
        skip 'Sphinx is not installed'
    fi
}

@test 'build/install el7 RPMs' {
    scope full
    prerequisites_ok centos_7ch
    img=${ch_imgdir}/centos_7ch
    image_ok "$img"
    rm -rf --one-file-system "${BATS_TMPDIR}/rpmbuild"

    # Build and install RPMs into CentOS 7 image.
    (cd .. && packaging/fedora/build --install "$img" \
                                     --rpmbuild="$BATS_TMPDIR/rpmbuild" HEAD)
}

@test 'check el7 RPM files' {
    scope full
    prerequisites_ok centos_7ch
    img=${ch_imgdir}/centos_7ch
    # Do installed RPMs look sane?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-builder'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-doc'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-run'* ]]
    [[ $output = *'/usr/lib/charliecloud/base.sh'* ]]
    [[ $output = *'/usr/share/man/man7/charliecloud.7.gz'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-builder"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-image'* ]]
    [[ $output = *'/usr/lib/charliecloud/charliecloud.py'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-debuginfo"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/lib/debug/usr/bin/ch-run.debug'* ]]
    [[ $output = *'/usr/lib/debug/usr/libexec/charliecloud/test/sotest/lib/libsotest.so.1.0.debug'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-doc"
    echo "$output"
    [[ $output = *'/usr/share/doc/charliecloud-'*'/html'* ]]
    [[ $output = *'/usr/share/doc/charliecloud-'*'/examples/lammps/Dockerfile'* ]]
}

@test 'remove el7 RPMs' {
    scope full
    prerequisites_ok centos_7ch
    img=${ch_imgdir}/centos_7ch
    # Uninstall to avoid interfering with the rest of the test suite.
    run ch-run -w "$img" -- rpm -v --erase charliecloud-test \
                                           charliecloud-debuginfo \
                                           charliecloud-doc \
                                           charliecloud-builder \
                                           charliecloud
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-doc'* ]]

    # All gone?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '' ]]
}

@test 'build/install el8 RPMS' {
    scope standard
    prerequisites_ok almalinux_8ch
    img=${ch_imgdir}/almalinux_8ch
    image_ok "$img"
    rm -Rf --one-file-system "${BATS_TMPDIR}/rpmbuild"

    # Build and install RPMs into AlmaLinux 8 image.
    (cd .. && packaging/fedora/build --install "$img" \
                                     --rpmbuild="$BATS_TMPDIR/rpmbuild" HEAD)
}

@test 'check el8 RPM files' {
    scope standard
    prerequisites_ok almalinux_8ch
    img=${ch_imgdir}/almalinux_8ch
    # Do installed RPMs look sane?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-builder'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-doc'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-run'* ]]
    [[ $output = *'/usr/lib/charliecloud/base.sh'* ]]
    [[ $output = *'/usr/share/man/man7/charliecloud.7.gz'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-builder"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-image'* ]]
    [[ $output = *'/usr/lib/charliecloud/charliecloud.py'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-debuginfo"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/lib/debug/usr/bin/ch-run'*'debug'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-doc"
    echo "$output"
    [[ $output = *'/usr/share/doc/charliecloud/html'* ]]
    [[ $output = *'/usr/share/doc/charliecloud/examples/lammps/Dockerfile'* ]]
}

@test 'remove el8 RPMs' {
    scope standard
    prerequisites_ok almalinux_8ch
    img=${ch_imgdir}/almalinux_8ch
    # Uninstall to avoid interfering with the rest of the test suite.
    run ch-run -w "$img" -- rpm -v --erase charliecloud-debuginfo \
                                           charliecloud-doc \
                                           charliecloud-builder \
                                           charliecloud
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-doc'* ]]

    # All gone?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '' ]]
}
