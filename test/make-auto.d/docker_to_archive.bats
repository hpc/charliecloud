@test 'ch-docker2archive %(tag)s' {
    scope %(scope)s
    %(arch_exclude)s
    need_docker
    if ( command -v squashfuse ); then
        archive="${ch_tardir}/%(tag)s.sqfs"
        ch-docker2squash %(tag)s "$ch_tardir"
    else
        archive="${ch_tardir}/%(tag)s.tar.gz"
        ch-docker2tar %(tag)s "$ch_tardir"
    fi
    archive_ls "$archive"
    archive_ok "$archive"
}
