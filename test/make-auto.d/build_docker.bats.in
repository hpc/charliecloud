@test 'ch-build %(tag)s' {
    scope %(scope)s
    %(arch_exclude)s
    need_docker %(tag)s
    ch-build -t %(tag)s --file="%(path)s" "%(dirname)s"
    sudo docker tag %(tag)s "%(tag)s:$ch_version_docker"
    docker_ok %(tag)s
}
