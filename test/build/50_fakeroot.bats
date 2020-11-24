load ../common

setup () {
    scope standard
    [[ $CH_BUILDER = ch-grow ]] || skip 'ch-grow only'
}

@test 'ch-grow --force: misc errors' {
    run ch-grow build --force --no-force-detect .
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = 'error'*'are incompatible'* ]]
}
