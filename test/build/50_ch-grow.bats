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

@test 'ch-grow delete' {
   run ch-grow list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output != *"delete-test"* ]]
  
	ch-grow build -t delete-test -f - . << 'EOF'
FROM 00_tiny
EOF
	
   run ch-grow list
	echo "$output"
	[[ $status -eq 0 ]]
	[[ $output = *"delete-test"* ]]
	
	ch-grow delete delete-test

	run ch-grow list
	echo "$output"
	[[ $status -eq 0 ]]
	[[ $output != *"delete-test"* ]]
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

@test 'ch-grow build --bind' {
    run ch-grow --no-cache build -t build-bind -f - \
                -b ./fixtures -b ./fixtures:/mnt/9 . <<'EOF'
FROM 00_tiny
RUN mount
RUN ls -lR /mnt
RUN test -f /mnt/0/empty-file
RUN test -f /mnt/9/empty-file
EOF
    echo "$output"
    [[ $status -eq 0 ]]
}
