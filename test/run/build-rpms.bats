load ../common

@test 'build/install/uninstall RPMs' {
    skip 'issue #594'
    scope standard
    prerequisites_ok centos7
    [[ $CHTEST_GITWD ]] || skip "not in Git working directory"
    if ( ! command -v sphinx-build > /dev/null 2>&1 ); then
        pedantic_fail 'Sphinx is not installed'
    fi
    img=${ch_imgdir}/centos7

    # Build and install RPMs into CentOS 7 image.
    (cd .. && packaging/fedora/build --install --image="$img" \
                                     --rpmbuild="$BATS_TMPDIR/rpmbuild" HEAD)

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
    [[ $output = *'/usr/lib/charliecloud-'*'/base.sh'* ]]
    [[ $output = *'/usr/share/man/man1/charliecloud.1.gz'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-debuginfo"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/lib/debug/usr/bin/ch-run.debug'* ]]
    [[ $output = *'/usr/lib/debug/usr/lib/charliecloud-'*'/test/sotest/lib/libsotest.so.1.0.debug'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-test"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/lib/charliecloud-'*'/examples/mpi/lammps/Dockerfile'* ]]
    [[ $output = *'/usr/lib/charliecloud-'*'/test/Build.centos7xz'* ]]
    [[ $output = *'/usr/lib/charliecloud-'*'/test/sotest/lib/libsotest.so.1.0'* ]]

    # Uninstall to avoid interfering with the rest of the test suite.
    run ch-run -w "$img" -- rpm -v --erase charliecloud-test \
                                           charliecloud-debuginfo \
                                           charliecloud
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-test-'* ]]

    # All gone?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '' ]]
}
