@test 'docker pull %(tag)s' {
    scope %(scope)s
    %(arch_exclude)s
    need_docker %(tag)s
    sudo docker pull %(addr)s
    sudo docker tag %(addr)s %(tag)s
    sudo docker tag %(tag)s "%(tag)s:${ch_version_docker}"
    docker_ok %(tag)s
}
