load ../common

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
}

@test 'ch-image common options' {
    # no common options
    run ch-image storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *'verbose level'* ]]

    # before only
    run ch-image -vv storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 2'* ]]

    # after only
    run ch-image storage-path -vv
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 2'* ]]

    # before and after; after wins
    run ch-image -vv storage-path -v
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 1'* ]]
}

@test 'ch-image delete' {
    # delete/test image doesn't exist
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"delete/test"* ]]
  
    # builds image 
    # called delete/test to check name parsing
	 ch-image build -t delete/test -f - . << 'EOF'
FROM 00_tiny
EOF
    run ch-image list
	 echo "$output"
	 [[ $status -eq 0 ]]
	 [[ $output = *"delete/test"* ]]
	
    # delete image 
    ch-image delete delete/test
    run ch-image list
  	 echo "$output"
	 [[ $status -eq 0 ]]
  	 [[ $output != *"delete/test"* ]]
}

@test 'ch-image list' {
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"00_tiny"* ]]
}

@test 'ch-image storage-path' {
    run ch-image storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = /* ]]                                        # absolute path
    [[ $CH_IMAGE_STORAGE && $output = "$CH_IMAGE_STORAGE" ]]  # match what we set
}

@test 'ch-image build --bind' {
    run ch-image --no-cache build -t build-bind -f - \
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
