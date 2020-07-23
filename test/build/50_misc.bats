load ../common

@test 'ch-build --builder-info' {
    scope standard
    ch-build --builder-info
}

@test 'ch-grow --list' {    
    if [[ $CH_BUILDER = none ]]; then
        skip 'no builder'
    else
        scope standard
        run ch-grow --list
        echo "$output"
        [[ $status -eq 0 ]] 
        [[ $output = *"hello"* ]]
    fi
}

@test 'sotest executable works' {
    scope quick
    export LD_LIBRARY_PATH=./sotest
    ldd sotest/sotest
    sotest/sotest
}
