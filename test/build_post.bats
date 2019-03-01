load common

@test 'build RPMs' {
    scope standard
    [[ -d ../.git ]] || skip "not in Git working directory"
    img=${ch_imgdir}/centos7

    # Build and install RPMs into CentOS 7 image.
    (cd .. && packaging/fedora/build --install --image="$img" \
                                  --rpmbuild="$BATS_TMPDIR/rpmbuild" HEAD)

    # Do installed RPMs look sane?
    run ch-run "$img" -- rpm -qa "charliecloud*"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'charliecloud-'* ]]
    [[ $output = *'charliecloud-doc-'* ]]
    [[ $output = *'charliecloud-debuginfo-'* ]]
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
    run ch-run "$img" -- rpm -ql "charliecloud-doc"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'/usr/libexec/charliecloud/examples/mpi/lammps/Dockerfile'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/Build.centos7xz'* ]]
    [[ $output = *'/usr/libexec/charliecloud/test/sotest/lib/libsotest.so.1.0'* ]]
}

@test 'nothing unexpected in tarball directory' {
    scope quick
    run find "$ch_tardir" -mindepth 1 \
        -not \( -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.pq_missing' \)
    echo "$output"
    [[ $output = '' ]]
}
