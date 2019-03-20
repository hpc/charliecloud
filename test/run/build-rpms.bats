load ../common

@test 'build/install/uninstall RPMs' {
    scope standard
    prerequisites_ok centos7
    [[ -d ../.git ]] || skip "not in Git working directory"
    command -v sphinx-build > /dev/null 2>&1 || skip 'Sphinx is not installed'
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
    [[ $output = *'charliecloud-devel-'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/bin/ch-run'* ]]
    [[ $output = *'/usr/libexec/charliecloud/base.sh'* ]]
    [[ $output = *'/usr/share/man/man1/charliecloud.1.gz'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-debuginfo"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/lib/debug/usr/bin/ch-run.debug'* ]]
    [[ $output = *'/usr/lib/debug/usr/libexec/charliecloud/test/sotest/lib/libsotest.so.1.0.debug'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-test"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/libexec/charliecloud/examples/mpi/lammps/Dockerfile'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/Build.centos7xz'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/sotest/lib/libsotest.so.1.0'* ]]
    run ch-run "$img" -- rpm -ql "charliecloud-devel"
    echo "$output"
    [[ $output = *'/usr/libexec/charliecloud/examples/mpi/mpihello/hello.c'* ]]
    [[ $output = *'/usr/libexec/charliecloud/examples/syscalls/pivot_root.c'* ]]
    [[ $output = *'/usr/libexec/charliecloud/examples/syscalls/userns.c'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/chtest/chroot-escape.c'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/chtest/mknods.c'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/chtest/setgroups.c'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/chtest/setuid.c'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/sotest/sotest.c'* ]]

    # Uninstall to avoid interfering with the rest of the test suite.
    run ch-run -w "$img" -- rpm -v --erase charliecloud-devel \
                                           charliecloud-debuginfo \
                                           charliecloud-test \
                                           charliecloud
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
    [[ $output = *'charliecloud-test-'* ]]
    [[ $output = *'charliecloud-devel-'* ]]

    # All gone?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = '' ]]
}
