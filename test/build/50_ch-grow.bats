load ../common

setup () {
    scope standard
    [[ $CH_BUILDER = ch-grow ]] || skip 'ch-grow only'
}

@test 'ch-grow common options' {
    # no common options
    run ch-grow storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *'verbose level'* ]]

    # before only
    run ch-grow -vv storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 2'* ]]

    # after only
    run ch-grow storage-path -vv
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 2'* ]]

    # before and after; after wins
    run ch-grow -vv storage-path -v
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 1'* ]]
}

@test 'ch-grow list' {
    run ch-grow list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"00_tiny"* ]]
}

@test 'ch-grow storage-path' {
    run ch-grow storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = /* ]]                                      # absolute path
    [[ $CH_GROW_STORAGE && $output = "$CH_GROW_STORAGE" ]]  # match what we set
}
