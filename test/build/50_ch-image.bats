load ../common

setup () {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
}

tmpimg_build () {
  for img in "$@"; do
    ch-image build -t "$img" -f - . << 'EOF'
FROM alpine:3.17
EOF
    run ch-image list
    [[ $status -eq 0 ]]
    [[ $output == *"$img"* ]]
  done
}


@test 'ch-image common options' {
    # no common options
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *'verbose level'* ]]

    # before only
    run ch-image -vv list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 2'* ]]

    # after only
    run ch-image list -vv
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 2'* ]]

    # before and after; after wins
    run ch-image -vv list -v
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 1'* ]]

    # unset debug in preparation for “--quiet” tests
    unset CH_IMAGE_DEBUG

    # test gestalt logging
    run ch-image gestalt logging
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"info"* ]]
    [[ $output = *'warning: warning'* ]]
    [[ $output = *'error: error'* ]]

    # quiet level 1
    run ch-image gestalt -q logging
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"info"* ]]
    [[ $output = *'warning: warning'* ]]
    [[ $output = *'error: error'* ]]

    # quiet level 2
    run ch-image build --force seccomp -t tmpimg -qq -f - . << 'EOF'
FROM alpine:3.17
RUN echo 'this is stdout'
RUN echo 'this is stderr' 1>&2
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"Dependencies resolved."* ]]
    [[ $output != *"grown in 4 instructions: tmpimg"* ]]

    # quiet level 3
    run ch-image gestalt logging -qqq
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *'info'* ]]
    [[ $output != *'warning: warning'* ]]
    [[ $output != *'error: error'* ]]

    # failure at quiet level 3
    run ch-image gestalt logging -qqq --fail
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output != *'info'* ]]
    [[ $output != *'warning: warning'* ]]
    [[ $output != *'error: error'* ]]
    [[ $output = *'error: the program failed inexplicably'* ]]
}


@test 'ch-image delete' {
    # Verify image doesn’t exist.
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"delete/test"* ]]

    # Build image. It’s called called delete/test to check ref parsing with
    # slash present.
    ch-image build -t delete/test -f - . << 'EOF'
FROM alpine:3.17
FROM alpine:3.17
FROM alpine:3.17
FROM alpine:3.17
EOF
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"delete/test"* ]]
    [[ $output = *"delete/test_stage0"* ]]
    [[ $output = *"delete/test_stage1"* ]]
    [[ $output = *"delete/test_stage2"* ]]

    # Delete image.
    ch-image delete delete/test
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"delete/test"* ]]
    [[ $output != *"delete/test_stage0"* ]]
    [[ $output != *"delete/test_stage1"* ]]
    [[ $output != *"delete/test_stage2"* ]]

    tmpimg_build tmpimg1 tmpimg2
    ch-image delete tmpimg1 tmpimg2
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"tmpimg1"* ]]
    [[ $output != *"tmpimg2"* ]]

    # Delete list of images with invalid image
    tmpimg_build tmpimg1 tmpimg2
    run ch-image delete tmpimg1 doesnotexist tmpimg2
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output == *"deleting image: tmpimg1"* ]]
    [[ $output == *"error: no matching image, can"?"t delete: doesnotexist"* ]]
    [[ $output == *"deleting image: tmpimg2"* ]]
    [[ $output == *"error: unable to delete 1 invalid image(s)"* ]]

    # Delete list of images with multiple invalid images
    tmpimg_build tmpimg1 tmpimg2
    run ch-image delete tmpimg1 doesnotexist tmpimg2 doesnotexist2
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output == *"deleting image: tmpimg1"* ]]
    [[ $output == *"error: no matching image, can"?"t delete: doesnotexist"* ]]
    [[ $output == *"deleting image: tmpimg2"* ]]
    [[ $output == *"error: no matching image, can"?"t delete: doesnotexist2"* ]]
    [[ $output == *"error: unable to delete 2 invalid image(s)"* ]]
}


@test 'broken image delete' {
    # Verify image doesn’t exist.
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"deletetest"* ]]

    # Build image.
    ch-image build -t deletetest -f - . << 'EOF'
FROM alpine:3.17
EOF
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"deletetest"* ]]

    # Break image.
    rmdir "$CH_IMAGE_STORAGE"/img/deletetest/dev

    # Delete image.
    ch-image delete deletetest
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"deletetest"* ]]
}


@test 'broken image overwrite' {
    # Build image.
    ch-image build -t tmpimg -f - . << 'EOF'
FROM alpine:3.17
EOF

    # Break image.
    rmdir "$CH_IMAGE_STORAGE"/img/tmpimg/dev

    # Rebuild image.
    ch-image build -t tmpimg -f - . << 'EOF'
FROM alpine:3.17
EOF
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"tmpimg"* ]]
}


@test 'ch-image import' {
    # Note: We don’t test importing a real image because (1) when this is run
    # during the build phase there aren’t any unpacked images and (2) I can’t
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
    [[ $output = *'conversion to tarbomb not needed'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # non-tarbomb
    (cd "$fixtures" && tar czvf standard.tar.gz nonempty)
    run ch-image import -v "${fixtures}/standard.tar.gz" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/standard.tar.gz"* ]]
    [[ $output = *'converting to tarbomb'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # non-tarbomb, but enclosing directory is a standard dir
    (cd "${fixtures}/nonempty" && tar czvf ../tricky.tar.gz bin)
    run ch-image import -v "${fixtures}/tricky.tar.gz" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/tricky.tar.gz"* ]]
    [[ $output = *'conversion to tarbomb not needed'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    ch-image delete imptest

    # empty, uncompressed tarfile
    (cd "${fixtures}" && tar cvf empty.tar empty)
    run ch-image import -v "${fixtures}/empty.tar" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/empty.tar"* ]]
    [[ $output = *'converting to tarbomb'* ]]
    [[ $output = *'warning: no metadata to load; using defaults'* ]]
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
    [[ $output = *"error: can"?"t copy: not found: /doesnotexist"* ]]

    # invalid destination reference
    run ch-image import -v "${fixtures}/empty" 'badchar*'
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: image ref syntax, char 8: badchar*'* ]]

    # non-empty file that’s not a tarball
    run ch-image import -v "${fixtures}/nonempty/ch/metadata.json" imptest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: cannot open: ${fixtures}/nonempty/ch/metadata.json"* ]]

    ## Clean up
    [[ ! -e "${CH_IMAGE_STORAGE}/img/imptest" ]]
    rm -Rfv --one-file-system "$fixtures"
}


@test 'ch-image list' {

    # list all images
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"alpine:3.17"* ]]

    # name does not exist remotely, in library
    run ch-image list doesnotexist:latest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # tag does not exist remotely, in library
    run ch-image list alpine:doesnotexist
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # name does not exist remotely, not in library
    run ch-image list charliecloud/doesnotexist:latest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # tag does not exist remotely, not in library
    run ch-image list charliecloud/metadata:doesnotexist
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # in storage, does not exist remotely
    run ch-image list argenv
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    yes'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # not in storage, exists remotely, fat manifest exists
    run ch-image list debian:buster-slim
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'remote arch-aware:   yes'* ]]
    [[ $output = *'archs available:'*'386'*'amd64'*'arm/v7'*'arm64/v8'* ]]

    # in storage, exists remotely, no fat manifest
    run ch-image list charliecloud/metadata:2021-01-15
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    yes'* ]]
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

    # scratch is weird and tells lies
    run ch-image list scratch
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'remote arch-aware:   yes'* ]]
}


@test 'ch-image reset' {
    CH_IMAGE_STORAGE="$BATS_TMPDIR"/sd-reset

    # Ensure our test storage dir doesn’t exist yet.
    [[ -e $CH_IMAGE_STORAGE ]] && rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

    # Put an image innit.
    ch-image pull alpine:3.17
    ls "$CH_IMAGE_STORAGE"

    # List images; should be only the one we just pulled.
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = "alpine:3.17" ]]

    # Reset.
    ch-image reset

    # Image storage directory should be empty now.
    expected=$(cat <<'EOF'
.:
bucache
bularge
dlcache
img
lock
ulcache
version

./bucache:

./bularge:

./dlcache:

./img:

./ulcache:
EOF
)
    actual=$(cd "$CH_IMAGE_STORAGE" && ls -1R)
    diff -u <(echo "$expected") <(echo "$actual")

    # Remove storage directory.
    rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

    # Reset again; should error.
    run ch-image reset
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"$CH_IMAGE_STORAGE not a builder storage"* ]]
}


@test 'ch-image storage-path' {
    run ch-image gestalt storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = /* ]]                                        # absolute path
    [[ $CH_IMAGE_STORAGE && $output = "$CH_IMAGE_STORAGE" ]]  # what we set
}


@test 'ch-image build --bind' {
    ch-image --no-cache build -t tmpimg -f - \
             -b "${PWD}/fixtures" -b ./fixtures:/mnt/0 . <<EOF
FROM alpine:3.17
RUN mount
RUN ls -lR '${PWD}/fixtures'
RUN test -f '${PWD}/fixtures/empty-file'
RUN ls -lR /mnt/0
RUN test -f /mnt/0/empty-file
EOF
}


@test 'ch-image build: metadata carry-forward' {
    arch_exclude aarch64  # test image not available
    arch_exclude ppc64le  # test image not available
    img=$CH_IMAGE_STORAGE/img/tmpimg

    # Print out current metadata, then update it.
    run ch-image build -v -t tmpimg -f - . <<'EOF'
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
    if [[ $CH_IMAGE_CACHE = disabled ]]; then
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
    fi

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
    diff -u -I '^.*"created":.*,$' - "${img}/ch/metadata.json" <<'EOF'
{
  "arch": "amd64",
  "arg": {
    "FAKEROOTDONTTRYCHOWN": "1",
    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "TAR_OPTIONS": "--no-same-owner"
  },
  "cwd": "/usr",
  "env": {
    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "ch_bar": "bar-ev",
    "ch_baz": "baz-ev",
    "ch_foo": "foo-ev"
  },
  "history": [
    {
      "created": "2020-04-24T01:05:35.458457398Z",
      "created_by": "/bin/sh -c #(nop) ADD file:a0afd0b0db7f9ee9496186ead087ec00edd1386ea8c018557d15720053f7308e in / "
    },
    {
      "created": "2020-04-24T01:05:35.807646609Z",
      "created_by": "/bin/sh -c #(nop)  CMD [\"/bin/sh\"]",
      "empty_layer": true
    },
    {
      "created": "2020-12-10T18:26:16.62246537Z",
      "created_by": "/bin/sh -c #(nop)  CMD [\"true\"]",
      "empty_layer": true
    },
    {
      "created": "2021-01-08T00:57:33.450706788Z",
      "created_by": "/bin/sh -c #(nop)  CMD [\"bar\" \"baz\"]",
      "empty_layer": true
    },
    {
      "created": "2021-01-08T00:57:33.675120552Z",
      "created_by": "/bin/sh -c #(nop)  ENTRYPOINT [\"/bin/echo\" \"foo\"]",
      "empty_layer": true
    },
    {
      "created": "2021-01-16T00:12:10.147564398Z",
      "created_by": "/bin/sh -c #(nop)  ENV ch_foo=foo-ev ch_bar=bar-ev",
      "empty_layer": true
    },
    {
      "created": "2021-01-16T00:12:10.340268945Z",
      "created_by": "/bin/sh -c #(nop)  EXPOSE 5309/udp 867",
      "empty_layer": true
    },
    {
      "created": "2021-01-16T00:12:10.590808975Z",
      "created_by": "/bin/sh -c #(nop)  HEALTHCHECK &{[\"CMD\" \"/bin/true\"] \"1m0s\" \"5s\" \"0s\" '\\x00'}",
      "empty_layer": true
    },
    {
      "created": "2021-01-16T00:12:10.749205247Z",
      "created_by": "/bin/sh -c #(nop)  LABEL ch_foo=foo-label ch_bar=bar-label",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:10.919558634Z",
      "created_by": "/bin/sh -c #(nop)  MAINTAINER charlie@example.com",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:11.080200702Z",
      "created_by": "/bin/sh -c #(nop)  ONBUILD RUN echo hello",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:11.900757214Z",
      "created_by": "/bin/sh -c echo hello",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:12.868439691Z",
      "created_by": "/bin/echo world",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:13.055783024Z",
      "created_by": "/bin/ash -c #(nop)  SHELL [/bin/ash -c]",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:13.473299627Z",
      "created_by": "/bin/ash -c #(nop)  STOPSIGNAL SIGWINCH",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:13.644005108Z",
      "created_by": "/bin/ash -c #(nop)  USER charlie:chargrp",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:13.83546594Z",
      "created_by": "/bin/ash -c #(nop) WORKDIR /mnt",
      "empty_layer": true
    },
    {
      "author": "charlie@example.com",
      "created": "2021-01-16T00:12:14.042791834Z",
      "created_by": "/bin/ash -c #(nop)  VOLUME [/mnt/foo /mnt/bar /mnt/foo]",
      "empty_layer": true
    },
    {
      "created": "2021-11-30T20:40:24Z",
      "created_by": "RUN.S echo \"cwd1: $PWD\""
    },
    {
      "created": "2021-11-30T20:40:24Z",
      "created_by": "WORKDIR /usr"
    },
    {
      "created": "2021-11-30T20:40:24Z",
      "created_by": "RUN.S echo \"cwd2: $PWD\""
    },
    {
      "created": "2021-11-30T20:40:24Z",
      "created_by": "RUN.S env | egrep '^(PATH=|ch_)' | sed -E 's/^/env1: /' | sort"
    },
    {
      "created": "2021-11-30T20:40:24Z",
      "created_by": "ENV ch_baz='baz-ev'"
    },
    {
      "created": "2021-11-30T20:40:24Z",
      "created_by": "RUN.S env | egrep '^(PATH=|ch_)' | sed -E 's/^/env2: /' | sort"
    },
    {
      "created": "2021-11-30T20:40:25Z",
      "created_by": "RUN.S echo \"shell1: $0\""
    },
    {
      "created": "2021-11-30T20:40:25Z",
      "created_by": "SHELL ['/bin/sh', '-v', '-c']"
    },
    {
      "created": "2021-11-30T20:40:25Z",
      "created_by": "RUN.S echo \"shell2: $0\""
    }
  ],
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


@test 'ch-image build: multistage with colon' {
cat <<'EOF' | ch-image --no-cache build -t tmpimg:tagged -f - .
FROM alpine:3.17
FROM alpine:3.16
COPY --from=0 /etc/os-release /
EOF
    ch-image delete tmpimg:tagged
}


@test 'ch-image build: failed RUN' {
    ch-image delete tmpimg || true

    # tr(1) works around a bug in Bash ≤4.4 (I think) that causes here docs
    # containing literal backslashes to parse incorrectly. See item “aa” in
    # the changelog [1] for version bash-5.0-alpha.
    #
    # [1]: https://git.savannah.gnu.org/cgit/bash.git/tree/CHANGES
    df=$(cat <<'EOF' | tr '%' "\\"
FROM alpine:3.17
RUN set -o noclobber %
 && echo hello > file_ %
 && mkdir dir_empty %
 && mkdir dir_nonempty %
 && mkfifo fifo_ %
EOF
        )

    ch-image build -t tmpimg - <<EOF && exit 1  # SC2314
${df}
 && false
EOF

    # This will succeed unless there’s leftover junk from failed RUN above.
    ch-image build -t tmpimg - <<EOF
${df}
 && true
EOF
}


@test 'ch-image build: failed COPY' {
    ch-image delete tmpimg || true

    # Set up fixtures.
    fixtures_dir="$BATS_TMPDIR"/copyfail
    rm -Rf --one-file-system "$fixtures_dir"
    mkdir "$fixtures_dir"
    touch "$fixtures_dir"/file_readable
    touch "$fixtures_dir"/file_unreadable
    chmod 000 "$fixtures_dir"/file_unreadable
    mkdir "$fixtures_dir"/dir_
    touch "$fixtures_dir"/dir_/file_

    # This will fail after the first file is already copied, because COPY is
    # non-atomic. We use an unreadable file because if the file didn’t exist,
    # COPY would fail out before starting.
    ch-image build -t tmpimg -f - "$fixtures_dir" <<'EOF' && exit 1
FROM alpine:3.17
COPY /file_readable /file_unreadable /
EOF

    # This will succeed unless there’s leftover junk from failed COPY above.
    # Otherwise, it will fail because can’t overwrite a file with a directory.
    ch-image build -t tmpimg -f - "$fixtures_dir" <<'EOF'
FROM alpine:3.17
COPY /dir_ /file_readable
EOF
}


@test 'storage directory versioning' {
   export CH_IMAGE_STORAGE="$BATS_TMPDIR"/sd-version

   # Ensure our test storage dir doesn’t exist yet.
   [[ -e $CH_IMAGE_STORAGE ]] && rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

   # Initialize by listing.
   run ch-image list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"initializing storage directory: v"*" ${CH_IMAGE_STORAGE}"* ]]

   # Read current version.
   v_current=$(cat "$CH_IMAGE_STORAGE"/version)

   # Version matches; success.
   run ch-image -v list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"found storage dir v${v_current}: ${CH_IMAGE_STORAGE}"* ]]

   # Fake version mismatch - non-upgradeable.
   echo '-1' > "$CH_IMAGE_STORAGE"/version
   cat "$CH_IMAGE_STORAGE"/version

   # Version mismatch; fail.
   run ch-image -v list
   echo "$output"
   [[ $status -eq 1 ]]
   [[ $output = *'error: incompatible storage directory v-1'* ]]

   # Reset.
   run ch-image reset
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"initializing storage directory: v${v_current} ${CH_IMAGE_STORAGE}"* ]]

   # Version matches again; success.
   run ch-image -v list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"found storage dir v${v_current}: ${CH_IMAGE_STORAGE}"* ]]
}


@test 'ch-run --unsafe' {
    my_storage=${BATS_TMPDIR}/unsafe

    # Default storage location.
    if [[ $CH_IMAGE_STORAGE = /var/tmp/$USER.ch ]]; then
        sold=$CH_IMAGE_STORAGE
        unset CH_IMAGE_STORAGE
        [[ ! -e .%3.17 ]]
        ch-run --unsafe alpine:3.17 -- /bin/true
        CH_IMAGE_STORAGE=$sold
    fi

    # Rest of test uses custom storage path.
    rm -rf "$my_storage"
    mkdir -p "$my_storage"/img
    ch-convert -i ch-image -o dir alpine:3.17 "${my_storage}/img/alpine+3.17"
    unset CH_IMAGE_STORAGE

    # Specified on command line.
    ch-run --unsafe -s "$my_storage" alpine:3.17 -- /bin/true

    # Specified with environment variable.
    export CH_IMAGE_STORAGE=$my_storage

    # Basic environment-variable specified.
    ch-run --unsafe alpine:3.17 -- /bin/true
}


@test 'ch-run storage errors' {
    run ch-run -v -w alpine:3.17 -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: --write invalid when running by name'* ]]

    run ch-run -v "$CH_IMAGE_STORAGE"/img/alpine+3.17 -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: can't run directory images from storage (hint: run by name)"* ]]

    run ch-run -v -s /doesnotexist alpine:3.17 -- /bin/true
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'warning: storage directory not found: /doesnotexist'* ]]
    [[ $output = *"error: can't stat: alpine:3.17: No such file or directory"* ]]
}


@test 'ch-run image in both storage and cwd' {
    cd "$BATS_TMPDIR"

    # Set up a fixure image in $CWD that causes a collision with the named
    # image, and that’s missing /bin/true so it pukes if we try to run it.
    # That is, in both cases, we want run-by-name to win.
    rm -rf ./alpine+3.17
    ch-convert -i ch-image -o dir alpine:3.17 ./alpine+3.17
    rm ./alpine+3.17/bin/true

    # Default.
    ch-run alpine:3.17 -- /bin/true

    # With --unsafe.
    ch-run --unsafe alpine:3.17 -- /bin/true
}


@test "IMPORT cache miss" {  # issue #1638
    [[ $CH_IMAGE_CACHE = enabled ]] || skip 'build cache enabled only'

    ch-convert alpine:3.17 "$BATS_TMPDIR"/alpine317.tar.gz
    ch-convert alpine:3.16 "$BATS_TMPDIR"/alpine316.tar.gz

    export CH_IMAGE_STORAGE=$BATS_TMPDIR/import_1638
    rm -Rf --one-file-system "$CH_IMAGE_STORAGE"
    ch-image import "$BATS_TMPDIR"/alpine317.tar.gz alpine:3.17
    ch-image import "$BATS_TMPDIR"/alpine316.tar.gz alpine:3.16

    df1=$BATS_TMPDIR/import_1638.1.df
    cat > "$df1" <<'EOF'
FROM alpine:3.17
RUN true
EOF
    df2=$BATS_TMPDIR/import_1638.2.df
    cat > "$df2" <<'EOF'
FROM alpine:3.16
RUN true
EOF

    echo
    echo '*** Build once: miss'
    run ch-image build -t tmpimg -f "$df1" "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.17'* ]]
    [[ $output = *'2. RUN.S true'* ]]

    echo
    echo '*** Build again: hit'
    run ch-image build -t tmpimg -f "$df1" "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.17'* ]]
    [[ $output = *'2* RUN.S true'* ]]

    echo
    echo '*** Build a 3rd time with the second base image: should now miss'
    run ch-image build -t tmpimg -f "$df2" "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.16'* ]]
    [[ $output = *'2. RUN.S true'* ]]
}
