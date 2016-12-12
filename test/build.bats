load common

@test 'create tarball directory if needed' {
    mkdir -p $TARDIR
}

@test 'executables --help' {
    docker-build --help
    ch-docker2tar --help
    ch-tar2dir --help
    ch-dockerfile2dir --help
}

@test 'docker-build' {
    cd chtest
    docker-build -t chtest ../..
    docker_ok chtest
}

@test 'docker-build --pull' {
    # this may get a new image, if edge has been updated
    docker-build --pull -t alpineedge --file=./Dockerfile.alpineedge ..
    # this very probably will not
    docker-build --pull -t alpineedge --file=./Dockerfile.alpineedge ..
}

@test 'ch-dockerfile2dir' {
    # This test unpacks into $TARDIR so we don't put anything in $IMGDIR at
    # build time. It removes the image on completion.
    TAR=$CHTEST_TARBALL
    IMG=$TARDIR/chtest
    [[ ! -e $IMG ]]
    cd chtest
    # Dockerfile expected in $CWD
    ch-dockerfile2dir ../.. $TARDIR
    docker_ok chtest
    image_ok $IMG
    # Same, overwrite
    ch-dockerfile2dir ../.. $TARDIR
    docker_ok chtest
    image_ok $IMG
    # Remove since we don't want it hanging around later
    rm -Rf $TAR $IMG
}
