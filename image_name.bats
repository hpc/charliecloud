load test/common

@test 'run image by name' {
    run ch-run 00_tiny -- echo foo
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "foo" ]]
}

@test 'ch-run specify storage' {
    mkdir /var/tmp/foo
    ch-convert -i ch-image -o dir 00_tiny /var/tmp/foo/00_tiny
    run ch-run -s /var/tmp/foo 00_tiny -- echo foo
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "foo" ]]

    rm -rf /var/tmp/foo
}

@test 'new ch-run errors' {
    run ch-run -w 00_tiny -- echo foo
    echo "$output"
    [[ $status -eq 1 ]]
    [[  $output = *"error: Cannot write to storage"* ]]
    
    run ch-run /var/tmp/"$USER.ch"/img/00_tiny -- echo foo
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: Specified path is in storage"* ]]
}
