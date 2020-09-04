load ../common

image_ref_parse () {
    # Try to parse image ref $1; expected output is provided on stdin and
    # expected exit code in $2.
    ref=$1
    retcode_expected=$2
    echo "--- parsing: ${ref}"
    set +e
    out=$(ch-grow pull --parse-only "$ref" 2>&1)
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
    scope standard
    if ( ! ch-grow --dependencies ); then
        [[ $CH_BUILDER != ch-grow ]]
        skip "ch-grow missing dependencies"
    fi

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
EOF

    # missing port number
    cat <<'EOF' | image_ref_parse 'example.com:/path1/name' 1
error: image ref syntax, char 13: example.com:/path1/name
EOF

    # path with leading slash
    cat <<'EOF' | image_ref_parse '/path1/name' 1
error: image ref syntax, char 1: /path1/name
EOF

    # path but no name
    cat <<'EOF' | image_ref_parse 'path1/' 1
error: image ref syntax, at end: path1/
EOF

    # bad digest algorithm
    cat <<'EOF' | image_ref_parse 'name@sha512:feeddad' 1
error: image ref syntax, char 5: name@sha512:feeddad
EOF

    # both tag and digest
    cat <<'EOF' | image_ref_parse 'name:tag@sha512:feeddad' 1
error: image ref syntax, char 9: name:tag@sha512:feeddad
EOF
}

@test 'pull image with symlink' {
    # Validate that if a prior layer contains a symlink and a subsequent layer
    # contains a regular file at the same path, the symlink is replaced with a
    # regular file and the symlink target is unchanged. See issue #819.
    scope standard
    if ( ! ch-grow --dependencies ); then
        [[ $CH_BUILDER != ch-grow ]]
        skip "ch-grow missing dependencies"
    fi

    img=$BATS_TMPDIR/charliecloud%symlink

    ch-grow pull charliecloud/symlink "$img"
    ls -lh "${img}/test"

    # /test/target should be a regular file with contents "target"
    run stat -c '%F' "${img}/test/target"
    [[ $status -eq 0 ]]
    echo "$output"
    [[ $output = 'regular file' ]]
    [[ $(cat "${img}/test/target") = 'target' ]]

    # /test/source should be a regular file with contents "regular"
    run stat -c '%F' "${img}/test/source"
    [[ $status -eq 0 ]]
    echo "$output"
    [[ $output = 'regular file' ]]
    [[ $(cat "${img}/test/source") = 'regular' ]]
}
