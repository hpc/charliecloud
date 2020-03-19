load ../common

setup () {
    [[ $CHTEST_GITWD ]] || skip "not in Git working directory"
    if     ! command -v sphinx-build > /dev/null 2>&1 \
        && ! command -v sphinx-build-3.6 > /dev/null 2>&1; then
        pedantic_fail 'Sphinx is not installed'
    fi
}

@test 'build/install epepel7 RPMs' {
    scope standard
    prerequisites_ok centos7
    if [[ -d ${BATS_TMPDIR}/rpmbuild/SOURCES/charliecloud ]]; then
        rm -rf "${BATS_TMPDIR}/rpmbuild/SOURCES/charliecloud"
    fi
    img=${ch_imgdir}/centos7
    mkdir -p "${img}/charliecloud"

    # Build and install RPMs into CentOS 7 image.
    (cd .. && packaging/fedora/build --install --image="$img" \
                                     --rpmbuild="$BATS_TMPDIR/rpmbuild" HEAD)
}

@test 'check epel7 RPM files' {
    img=${ch_imgdir}/centos7
    # Do installed RPMs look sane?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-test-'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-run'* ]]
    [[ $output = *'/usr/lib64/charliecloud/base.sh'* ]]
    [[ $output = *'/usr/share/doc/charliecloud-'*'/examples/lammps/Dockerfile'* ]]
    [[ $output = *'/usr/share/man/man1/charliecloud.1.gz'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-debuginfo"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/lib/debug/usr/bin/ch-run.debug'* ]]
    [[ $output = *'/usr/lib/debug/usr/libexec/charliecloud/test/sotest/lib/libsotest.so.1.0.debug'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-test"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-test'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/Build.centos7xz'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/sotest/lib/libsotest.so.1.0'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-doc"
    echo "$output"
    [[ $output = *'/usr/share/doc/charliecloud-'*'/html'* ]]
}

@test 'remove epel7 RPMs' {
    img=${ch_imgdir}/centos7
    # Uninstall to avoid interfering with the rest of the test suite.
    run ch-run -w "$img" -- rpm -v --erase charliecloud-test \
                                           charliecloud-debuginfo \
                                           charliecloud-doc \
                                           charliecloud
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-test-'* ]]

    # All gone?
    rm -rf "${img}/charliecloud"
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '' ]]
}

@test 'build/install epel8 RPMS' {
    scope standard
    prerequisites_ok centos8
    if [[ -d ${BATS_TMPDIR}/rpmbuild/SOURCES/charliecloud ]]; then
        rm -rf "${BATS_TMPDIR}/rpmbuild/SOURCES/charliecloud"
    fi
    img=${ch_imgdir}/centos8
    mkdir -p "${img}/charliecloud"

    # Build and install RPMs into CentOS 8 image.
    (cd .. && packaging/fedora/build --install --image="$img" \
                                     --rpmbuild="$BATS_TMPDIR/rpmbuild" HEAD)
}

@test 'check epel8 RPM files' {
    img=${ch_imgdir}/centos8
    # Do installed RPMs look sane?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-test-'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-run'* ]]
    [[ $output = *'/usr/lib64/charliecloud/base.sh'* ]]
    [[ $output = *'/usr/share/doc/charliecloud-'*'/examples/lammps/Dockerfile'* ]]
    [[ $output = *'/usr/share/man/man1/charliecloud.1.gz'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-debuginfo"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/lib/debug/usr/bin/ch-run.debug'* ]]
    [[ $output = *'/usr/lib/debug/usr/libexec/charliecloud/test/sotest/lib/libsotest.so.1.0.debug'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-test"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-test'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/Build.centos7xz'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/sotest/lib/libsotest.so.1.0'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-doc"
    echo "$output"
    [[ $output = *'/usr/share/doc/charliecloud-'*'/html'* ]]
}

@test 'remove epel8 RPMs' {
    img=${ch_imgdir}/centos8
    # Uninstall to avoid interfering with the rest of the test suite.
    run ch-run -w "$img" -- rpm -v --erase charliecloud-test \
                                           charliecloud-debuginfo \
                                           charliecloud-doc \
                                           charliecloud
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-test-'* ]]

    # All gone?
    rm -rf "${img}/charliecloud"
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '' ]]
}
