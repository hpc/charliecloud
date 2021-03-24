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
    # verify delete/test image doesn't exist
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"delete/test"* ]]

    # Build image. It's called called delete/test to check ref parsing with
    # slash present.
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
                -b ./fixtures -b ./fixtures:/mnt/9 . <<EOF
FROM 00_tiny
RUN mount
RUN ls -lR /mnt
RUN test -f ${PWD}/empty-file
RUN test -f /mnt/9/empty-file
EOF
    echo "$output"
    [[ $status -eq 0 ]]
}

@test 'ch-image build: metadata carry-forward' {
    img=$CH_IMAGE_STORAGE/img/build-metadata

    # Print out current metadata, then update it.
    run ch-image build --no-cache -t build-metadata -f - . <<'EOF'
FROM charliecloud/metadata:2021-01-15
RUN echo "cwd1: $PWD"
WORKDIR /usr
RUN echo "cwd2: $PWD"
RUN env | egrep '^(PATH=|ch_)' | sed -E 's/^/env1: /' | sort
ENV ch_baz=baz-ev
RUN env | egrep '^(PATH=|ch_)' | sed -E 's/^/env2: /' | sort
RUN echo "shell1: $0"
SHELL ["/bin/sh", "-v", "-c"]
RUN echo "shell2: $0"
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'cwd1: /mnt'* ]]
    [[ $output = *'cwd2: /usr'* ]]
    [[ $output = *'env1: PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'* ]]
    [[ $output = *'env1: ch_bar=bar-ev'* ]]
    [[ $output = *'env1: ch_foo=foo-ev'* ]]
    [[ $output = *'env2: PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'* ]]
    [[ $output = *'env2: ch_bar=bar-ev'* ]]
    [[ $output = *'env2: ch_baz=baz-ev'* ]]
    [[ $output = *'env2: ch_foo=foo-ev'* ]]
    [[ $output = *'shell1: /bin/ash'* ]]
    [[ $output = *'shell2: /bin/sh'* ]]

    # Correct files?
    diff -u - <(ls "${img}/ch") <<'EOF'
config.pulled.json
environment
metadata.json
EOF

    # Volume mount points exist?
    ls -lh "${img}/mnt"
    test -d "${img}/mnt/foo"
    test -d "${img}/mnt/bar"

    # /ch/environment contents
    diff -u - "${img}/ch/environment" <<'EOF'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ch_bar=bar-ev
ch_baz=baz-ev
ch_foo=foo-ev
EOF

    # /ch/metadata.json contents
    diff -u - "${img}/ch/metadata.json" <<'EOF'
{
  "arch": "amd64",
  "cwd": "/usr",
  "env": {
    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "ch_bar": "bar-ev",
    "ch_baz": "baz-ev",
    "ch_foo": "foo-ev"
  },
  "labels": {
    "ch_bar": "bar-label",
    "ch_foo": "foo-label"
  },
  "shell": [
    "/bin/sh",
    "-v",
    "-c"
  ],
  "volumes": [
    "/mnt/bar",
    "/mnt/foo"
  ]
}
EOF
}
