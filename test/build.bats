load common

@test 'executables --help' {
    docker-build --help
    ch-docker2tar --help
    ch-tar2dir --help
    ch-dockerfile2dir --help
}

@test 'docker-build' {
    cd chtest
    docker-build -t $USER/chtest ../..
    docker_ok $USER/chtest
}

@test 'docker-build --pull' {
    # this may get a new image, if edge has been updated
    docker-build --pull -t $USER/alpineedge --file=./Dockerfile.alpineedge ..
    # this very probably will not
    docker-build --pull -t $USER/alpineedge --file=./Dockerfile.alpineedge ..
}

@test 'ch-dockerfile2dir' {
    cd chtest
    # Dockerfile expected in $CWD
    ch-dockerfile2dir ../.. $IMGDIR
    docker_ok $USER/chtest
    tarball_ok $CHTEST_TARBALL
    image_ok $CHTEST_IMG
    # Same, overwrite
    ch-dockerfile2dir ../.. $IMGDIR
    docker_ok $USER/chtest
    tarball_ok $CHTEST_TARBALL
    image_ok $CHTEST_IMG
}
