load ../common

@test 'sotest executable works' {
    scope quick
    [[ $ch_libc = glibc ]] || skip 'glibc only'
    export LD_LIBRARY_PATH=./sotest
    ldd sotest/sotest
    sotest/sotest
}
