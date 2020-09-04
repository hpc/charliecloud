load ../common

@test 'ch-build --builder-info' {
    scope standard
    ch-build --builder-info
}

@test 'ch-grow list' {
    scope standard
    [[ $CH_BUILDER = ch-grow ]] || skip 'ch-grow only'

    run ch-grow list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"00_tiny"* ]]
}

@test 'sotest executable works' {
    scope quick
    export LD_LIBRARY_PATH=./sotest
    ldd sotest/sotest
    sotest/sotest
}
