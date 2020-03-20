load ../common

@test 'ch-build --builder-info' {
    scope standard
    ch-build --builder-info
}

@test 'sotest executable works' {
    scope quick
    export LD_LIBRARY_PATH=./sotest
    ldd sotest/sotest
    sotest/sotest
}
