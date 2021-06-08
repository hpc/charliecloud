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

@test 'ch-image import' {
    # Note: We don't test importing a real image because (1) when this is run
    # during the build phase there aren't any unpacked images and (2) I can't
    # think of a way import could fail that would be real image-specific.

    ## Test image (not runnable)
    fixtures=${BATS_TMPDIR}/import
    rm -Rfv --one-file-system "$fixtures"
    mkdir "$fixtures" \
          "${fixtures}/empty" \
          "${fixtures}/nonempty" \
          "${fixtures}/nonempty/ch" \
          "${fixtures}/nonempty/bin"
    (cd "$fixtures" && ln -s nonempty nelink)
    touch "${fixtures}/nonempty/bin/foo"
    cat <<'EOF' > "${fixtures}/nonempty/ch/metadata.json"
{ "arch": "corn",
  "cwd": "/",
  "env": {},
  "labels": {},
  "shell": [
    "/bin/sh",
    "-c"
  ],
  "volumes": [] }
EOF
    ls -lhR "$fixtures"

    ## Tarballs

    # tarbomb
    (cd "${fixtures}/nonempty" && tar czvf ../bomb.tar.gz .)
    run ch-image import -v "${fixtures}/bomb.tar.gz" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/bomb.tar.gz"* ]]
    [[ $output != *'layers: single enclosing directory, using its contents'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # non-tarbomb
    (cd "$fixtures" && tar czvf standard.tar.gz nonempty)
    run ch-image import -v "${fixtures}/standard.tar.gz" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/standard.tar.gz"* ]]
    [[ $output = *'layers: single enclosing directory, using its contents'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # non-tarbomb, but enclosing directory is a standard dir
    (cd "${fixtures}/nonempty" && tar czvf ../tricky.tar.gz bin)
    run ch-image import -v "${fixtures}/tricky.tar.gz" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/tricky.tar.gz"* ]]
    [[ $output != *'layers: single enclosing directory, using its contents'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": null' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # empty, uncompressed tarfile
    (cd "${fixtures}" && tar cvf empty.tar empty)
    run ch-image import -v "${fixtures}/empty.tar" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/empty.tar"* ]]
    [[ $output = *'layers: single enclosing directory, using its contents'* ]]
    [[ $output = *'warning: no metadata to load; using defaults'* ]]
    grep -F '"arch": null' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    ## Directories

    # non-empty directory
    run ch-image import -v "${fixtures}/nonempty" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/nonempty"* ]]
    [[ $output = *"copying image: ${fixtures}/nonempty -> ${CH_IMAGE_STORAGE}/img/imptest"* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # empty directory
    run ch-image import -v "${fixtures}/empty" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/empty"* ]]
    [[ $output = *"copying image: ${fixtures}/empty -> ${CH_IMAGE_STORAGE}/img/imptest"* ]]
    [[ $output = *'warning: no metadata to load; using defaults'* ]]
    grep -F '"arch": null' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # symlink to directory
    run ch-image import -v "${fixtures}/nelink" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/nelink"* ]]
    [[ $output = *"copying image: ${fixtures}/nelink -> ${CH_IMAGE_STORAGE}/img/imptest"* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    ## Errors

    # input does not exist
    run ch-image import -v /doesnotexist imptest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: can't copy: not found: /doesnotexist"* ]]

    # invalid destination reference
    run ch-image import -v "${fixtures}/empty" 'badchar*'
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: image ref syntax, char 8: badchar*'* ]]

    # non-empty file that's not a tarball
    run ch-image import -v "${fixtures}/nonempty/ch/metadata.json" imptest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: cannot open: ${fixtures}/nonempty/ch/metadata.json"* ]]

    ## Clean up
    [[ ! -e "${CH_IMAGE_STORAGE}/img/imptest" ]]
    rm -Rfv --one-file-system "$fixtures"
}

@test 'ch-image list' {
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"00_tiny"* ]]

    ### IMAGE_REF ###

    # does not exist remotely
    run ch-image list foo:bar
    [[ $status -eq 1 ]]
    [[ $output = *'error'* ]]
    [[ $output = *'GET failed'* ]]
    [[ $output = *'expected status {200, 403} but got 400: Bad Request'* ]]

    # in storage, does not exist remotely, no fat manifest
    run ch-image list 00_tiny
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'in local storage:    yes'* ]]
    [[ $output = *'{200, 403} but got 400: Bad Request'* ]]

    # exists remotely, fat manifest exists
    run ch-image list debian:buster
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'remote arch-aware:   yes'* ]]
    [[ $output = *'archs available:'* ]]
    [[ $output = *'386 amd64 arm/v5 arm/v7 arm64/v8 mips64le ppc64le s390x'* ]]

    # exists remotely, no fat manifest
    run ch-image list charliecloud/metadata:2021-01-15 --no-cache
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'remote arch-aware:   no'* ]]
    [[ $output = *'archs available:     unknown'* ]]

    # exists remotely, fat manifest exists, no Linux architectures
    run ch-image list mcr.microsoft.com/windows:20H2
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'remote arch-aware:   yes'* ]]
    [[ $output = *'warning: no valid architectures found'* ]]
}

@test 'ch-image pull yolo arch' {
    # has fat manifest
    ch-image --arch=yolo     --no-cache pull alpine:latest
    ch-image --arch=host     --no-cache pull alpine:latest
    ch-image --arch=amd64    --no-cache pull alpine:latest
    ch-image --arch=arm64/v8 --no-cache pull alpine:latest

    # no fat manifest
    ch-image --arch=yolo  --no-cache pull charliecloud/metadata:2021-01-15
    ch-image --arch=amd64 --no-cache pull charliecloud/metadata:2021-01-15
    if [[ $(uname -m) == 'x86_64' ]]; then
        ch-image --arch=host --no-cache pull charliecloud/metadata:2021-01-15
        run ch-image --arch=arm64/v8 --no-cache pull charliecloud/metadata:2021-01-15
        echo "$output"
        [[ $status -eq 1 ]]
        [[ $output = *'error'* ]]
        [[ $output = *'image is architecture-unaware; try --arch=yolo (?)' ]]
    else
        skip 'host is not amd64'
    fi

    # requested arch does not exist
    run ch-image --arch=yolo/swag --no-cache pull centos:8
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error'* ]]
    [[ $output = *'requested arch unavailable:'* ]]
    [[ $output = *'yolo/swag not one of: amd64 arm64/v8 ppc64le'* ]]
}

@test 'ch-image reset' {
   export CH_IMAGE_STORAGE="$BATS_TMPDIR"/reset

   # Ensure our test storage dir doesn't exist yet.
   [[ ! -e $CH_IMAGE_STORAGE ]]

   # Put an image innit.
   ch-image pull alpine:3.9
   ls "$CH_IMAGE_STORAGE"

   # List images; should be only the one we just pulled.
   run ch-image list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = "alpine:3.9" ]]

   # Reset.
   ch-image reset

   # Image storage directory should be gone.
   ls "$CH_IMAGE_STORAGE" || true
   [[ ! -e $CH_IMAGE_STORAGE ]]

   # List images; should error with not found.
   run ch-image list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"does not exist: $CH_IMAGE_STORAGE"* ]]

   # Reset again; should error.
   run ch-image reset
   echo "$output"
   [[ $status -eq 1 ]]
   [[ $output = *"$CH_IMAGE_STORAGE not a builder storage"* ]]
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
                -b "${PWD}/fixtures" -b ./fixtures:/mnt/0 . <<EOF
FROM 00_tiny
RUN mount
RUN ls -lR '${PWD}/fixtures'
RUN test -f '${PWD}/fixtures/empty-file'
RUN ls -lR /mnt/0
RUN test -f /mnt/0/empty-file
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
