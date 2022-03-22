load ../common

setup () {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
}

image_ref_parse () {
    # Try to parse image ref $1; expected output is provided on stdin and
    # expected exit code in $2.
    ref=$1
    retcode_expected=$2
    echo "--- parsing: ${ref}"
    set +e
    out=$(ch-image pull --parse-only "$ref" 2>&1)
    retcode=$?
    set -e
    echo "--- return code: ${retcode}"
    echo '--- output:'
    echo "$out"
    if [[ $retcode -ne "$retcode_expected" ]]; then
        echo "fail: return code differs from expected ${retcode_expected}"
        exit 1
    fi
    diff -u - <(echo "$out")
}


@test 'image ref parsing' {
    # simplest
    cat <<'EOF' | image_ref_parse name 0
as string:    name
for filename: name
fields:
  host    None
  port    None
  path    []
  name    'name'
  tag     None
  digest  None
EOF

    # one-component path
    cat <<'EOF' | image_ref_parse path1/name 0
as string:    path1/name
for filename: path1%name
fields:
  host    None
  port    None
  path    ['path1']
  name    'name'
  tag     None
  digest  None
EOF

    # two-component path
    cat <<'EOF' | image_ref_parse path1/path2/name 0
as string:    path1/path2/name
for filename: path1%path2%name
fields:
  host    None
  port    None
  path    ['path1', 'path2']
  name    'name'
  tag     None
  digest  None
EOF

    # host with dot
    cat <<'EOF' | image_ref_parse example.com/name 0
as string:    example.com/name
for filename: example.com%name
fields:
  host    'example.com'
  port    None
  path    []
  name    'name'
  tag     None
  digest  None
EOF

    # host with dot, with port
    cat <<'EOF' | image_ref_parse example.com:8080/name 0
as string:    example.com:8080/name
for filename: example.com:8080%name
fields:
  host    'example.com'
  port    8080
  path    []
  name    'name'
  tag     None
  digest  None
EOF

    # host without dot, with port
    cat <<'EOF' | image_ref_parse examplecom:8080/name 0
as string:    examplecom:8080/name
for filename: examplecom:8080%name
fields:
  host    'examplecom'
  port    8080
  path    []
  name    'name'
  tag     None
  digest  None
EOF

    # no path, tag
    cat <<'EOF' | image_ref_parse name:tag 0
as string:    name:tag
for filename: name:tag
fields:
  host    None
  port    None
  path    []
  name    'name'
  tag     'tag'
  digest  None
EOF

    # no path, digest
    cat <<'EOF' | image_ref_parse name@sha256:feeddad 0
as string:    name@sha256:feeddad
for filename: name@sha256:feeddad
fields:
  host    None
  port    None
  path    []
  name    'name'
  tag     None
  digest  'feeddad'
EOF

    # everything, tagged
    cat <<'EOF' | image_ref_parse example.com:8080/path1/path2/name:tag 0
as string:    example.com:8080/path1/path2/name:tag
for filename: example.com:8080%path1%path2%name:tag
fields:
  host    'example.com'
  port    8080
  path    ['path1', 'path2']
  name    'name'
  tag     'tag'
  digest  None
EOF

    # everything, tagged, filename component
    cat <<'EOF' | image_ref_parse example.com:8080%path1%path2%name:tag 0
as string:    example.com:8080/path1/path2/name:tag
for filename: example.com:8080%path1%path2%name:tag
fields:
  host    'example.com'
  port    8080
  path    ['path1', 'path2']
  name    'name'
  tag     'tag'
  digest  None
EOF

    # everything, digest
    cat <<'EOF' | image_ref_parse example.com:8080/path1/path2/name@sha256:feeddad 0
as string:    example.com:8080/path1/path2/name@sha256:feeddad
for filename: example.com:8080%path1%path2%name@sha256:feeddad
fields:
  host    'example.com'
  port    8080
  path    ['path1', 'path2']
  name    'name'
  tag     None
  digest  'feeddad'
EOF

    # errors

    # invalid character in image name
    cat <<'EOF' | image_ref_parse 'name*' 1
error: image ref syntax, char 5: name*
hint: https://hpc.github.io/charliecloud/faq.html#how-do-i-specify-an-image-reference
EOF

    # missing port number
    cat <<'EOF' | image_ref_parse 'example.com:/path1/name' 1
error: image ref syntax, char 13: example.com:/path1/name
hint: https://hpc.github.io/charliecloud/faq.html#how-do-i-specify-an-image-reference
EOF

    # path with leading slash
    cat <<'EOF' | image_ref_parse '/path1/name' 1
error: image ref syntax, char 1: /path1/name
hint: https://hpc.github.io/charliecloud/faq.html#how-do-i-specify-an-image-reference
EOF

    # path but no name
    cat <<'EOF' | image_ref_parse 'path1/' 1
error: image ref syntax, at end: path1/
hint: https://hpc.github.io/charliecloud/faq.html#how-do-i-specify-an-image-reference
EOF

    # bad digest algorithm
    cat <<'EOF' | image_ref_parse 'name@sha512:feeddad' 1
error: image ref syntax, char 5: name@sha512:feeddad
hint: https://hpc.github.io/charliecloud/faq.html#how-do-i-specify-an-image-reference
EOF

    # both tag and digest
    cat <<'EOF' | image_ref_parse 'name:tag@sha512:feeddad' 1
error: image ref syntax, char 9: name:tag@sha512:feeddad
hint: https://hpc.github.io/charliecloud/faq.html#how-do-i-specify-an-image-reference
EOF
}

@test 'pull image with quirky files' {
    arch_exclude aarch64  # test image not available
    arch_exclude ppc64le  # test image not available
    # Validate that layers replace symlinks correctly. See
    # test/Dockerfile.symlink and issues #819 & #825.

    img=$BATS_TMPDIR/charliecloud%file-quirks

    ch-image pull charliecloud/file-quirks:2020-10-21 "$img"
    ls -lh "${img}/test"

    output_expected=$(cat <<'EOF'
regular file   'df_member'
symbolic link  'ds_link' -> 'ds_target'
regular file   'ds_target'
directory      'fd_member'
symbolic link  'fs_link' -> 'fs_target'
regular file   'fs_target'
symbolic link  'link_b0rken' -> 'doesnotexist'
symbolic link  'link_imageonly' -> '../test'
symbolic link  'link_self' -> 'link_self'
directory      'sd_link'
regular file   'sd_target'
regular file   'sf_link'
regular file   'sf_target'
symbolic link  'ss_link' -> 'ss_target2'
regular file   'ss_target1'
regular file   'ss_target2'
EOF
)

    cd "${img}/test"
    run stat -c '%-14F %N' -- *
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")
    cd -
}

@test 'pull images with uncommon manifests' {
    arch_exclude aarch64  # test image not available
    arch_exclude ppc64le  # test image not available
    if [[ -n $CH_REGY_DEFAULT_HOST ]]; then
        # Manifests seem to vary by registry; we need Docker Hub.
        skip 'default registry host set'
    fi

    storage="${BATS_TMPDIR}/tmp"
    cache=$storage/dlcache
    export CH_IMAGE_STORAGE=$storage

    # OCI manifest; see issue #1184.
    img=charliecloud/ocimanifest:2021-10-12
    ch-image pull "$img"

    # Manifest schema version one (v1); see issue #814. Use debian:squeeze
    # because 1) it always returns a v1 manifest schema (regardless of media
    # type specified), and 2) it isn't very large, thus keeps test time down.
    img=debian:squeeze
    ch-image pull "$img"
    grep -F '"schemaVersion": 1' "${cache}/${img}%skinny.manifest.json"

    rm -Rf --one-file-system "$storage"
}

@test 'pull from public repos' {
    if [[ -n $CH_REGY_DEFAULT_HOST ]]; then
        skip 'default registry host set'  # avoid Docker Hub
    fi
    if [[ -z $CI ]]; then
        # Verify we can reach the public internet, except on CI, where we
        # insist this should work.
        ping -c3 8.8.8.8 || skip "can't ping 8.8.8.8"
    fi

    # These images are selected to be official-ish and small. My rough goal is
    # to keep them under 10MiB uncompressed, but this isn't working great. It
    # may be worth our while to upload some small test images to these places.

    # Docker Hub: https://hub.docker.com/_/alpine
    ch-image pull registry-1.docker.io/library/alpine:latest

    # quay.io: https://quay.io/repository/quay/busybox
    ch-image pull quay.io/quay/busybox:latest

    # gitlab.com: https://gitlab.com/pages/hugo
    # FIXME: 50 MiB, try to do better; seems to be the slowest repo.
    ch-image pull registry.gitlab.com/pages/hugo:latest

    # Google Container Registry:
    # https://console.cloud.google.com/gcr/images/google-containers/GLOBAL
    # FIXME: "latest" tags do not work, but they do in Docker (issue #896)
    # FIXME: arch-aware pull does not work either (issue #1100)
    ch-image pull --arch=yolo gcr.io/google-containers/busybox:1.27

    # nVidia NGC: https://ngc.nvidia.com
    # FIXME: 96 MiB unpacked; also kind of slow
    # Note: Can't pull this image with LC_ALL=C under Python 3.6 (issue #970).
    ch-image pull nvcr.io/hpc/foldingathome/fah-gpu:7.6.21

    # Red Hat registry: https://catalog.redhat.com/software/containers/explore
    # FIXME: 77 MiB unpacked, should find a smaller public image
    ch-image pull registry.access.redhat.com/ubi7-minimal:latest

    # Microsoft Container Registry:
    # https://github.com/microsoft/containerregistry
    ch-image pull mcr.microsoft.com/mcr/hello-world:latest

    # Things not here (yet?):
    #
    # 1. Harbor (issue #899): Has a demo repo (https://demo.goharbor.io) that
    #    you can make an account on, but I couldn't find a public repo, and
    #    the demo repo gets reset every two days.
    #
    # 2. Docker registry container (https://hub.docker.com/_/registry): Would
    #    need to set up an instance.
    #
    # 3. Amazon public repo (issue #901,
    #    https://aws.amazon.com/blogs/containers/advice-for-customers-dealing-with-docker-hub-rate-limits-and-a-coming-soon-announcement/):
    #    Does not exist yet; coming "within weeks" of 2020-11-02.
    #
    # 4. Microsoft Azure registry [1] (issue #902): I could not find any
    #    public images. It seems that public pull is "currently a preview
    #    feature" as of 2020-11-06 [2].
    #
    #    [1]: https://azure.microsoft.com/en-us/services/container-registry
    #    [2]: https://docs.microsoft.com/en-us/azure/container-registry/container-registry-faq#how-do-i-enable-anonymous-pull-access
    #
    # 5. JFrog / Artifactory (https://jfrog.com/container-registry/): Could
    #    not find any public registry.
}

@test 'pull image with metadata' {
    arch_exclude aarch64  # test image not available
    arch_exclude ppc64le  # test image not available
    tag=2021-01-15
    name=charliecloud/metadata:$tag
    img=$CH_IMAGE_STORAGE/img/charliecloud%metadata:$tag

    ch-image pull "$name"

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
ch_foo=foo-ev
EOF

    # /ch/metadata.json contents
    diff -u -I '^.*"created":.*,$' - "${img}/ch/metadata.json" <<'EOF'
{
  "arch": "amd64",
  "cwd": "/mnt",
  "env": {
    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "ch_bar": "bar-ev",
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
    }
  ],
  "labels": {
    "ch_bar": "bar-label",
    "ch_foo": "foo-label"
  },
  "shell": [
    "/bin/ash",
    "-c"
  ],
  "volumes": [
    "/mnt/bar",
    "/mnt/foo"
  ]
}
EOF
}


@test 'pull by arch' {
    # Has fat manifest; requested arch exists. There's not much simple to look
    # for in the output, so just see if it works.
    ch-image --arch=yolo pull alpine:latest
    ch-image --arch=host pull alpine:latest
    ch-image --arch=amd64 pull alpine:latest
    ch-image --arch=arm64/v8 pull alpine:latest

    # Has fat manifest, but requested arch does not exist.
    run ch-image --arch=doesnotexist pull alpine:latest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'requested arch unavailable:'*'available:'* ]]

    # Delete it so we don't try to use a non-matching arch for other testing.
    ch-image delete alpine:latest

    # No fat manifest.
    ch-image --arch=yolo pull charliecloud/metadata:2021-01-15
    ch-image --arch=amd64 pull charliecloud/metadata:2021-01-15
    if [[ $(uname -m) == 'x86_64' ]]; then
        ch-image --arch=host pull charliecloud/metadata:2021-01-15
        run ch-image --arch=arm64/v8 pull charliecloud/metadata:2021-01-15
        echo "$output"
        [[ $status -eq 1 ]]
        [[ $output = *'image is architecture-unaware'*'consider --arch=yolo' ]]
    fi
}


@test 'pull images that do not exist' {
    if [[ -n $CH_REGY_DEFAULT_HOST ]]; then
        skip 'default registry host set'  # errors are Docker Hub specific
    fi

    # name does not exist remotely, in library
    run ch-image pull doesnotexist:latest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'registry-1.docker.io:443/library/doesnotexist:latest'* ]]

    # tag does not exist remotely, in library
    run ch-image pull alpine:doesnotexist
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'registry-1.docker.io:443/library/alpine:doesnotexist'* ]]

    # name does not exist remotely, not in library
    run ch-image pull charliecloud/doesnotexist:latest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'registry-1.docker.io:443/charliecloud/doesnotexist:latest'* ]]

    # tag does not exist remotely, not in library
    run ch-image pull charliecloud/metadata:doesnotexist
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'registry-1.docker.io:443/charliecloud/metadata:doesnotexist'* ]]
}
