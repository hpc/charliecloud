#!/bin/bash

# temporary test script for image ref parsing

set -e

PATH=$(readlink -f $(dirname "$0")/../bin):$PATH

yolo () {
    ref=$1
    retcode_expected=$2
    out_expected=$3
    echo "--- parsing: ${ref}"
    set +e
    out=$(ch-pull --parse-ref-only "$ref" 2>&1)
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

# simplest
cat <<'EOF' | yolo name 0
as string:    name
for filename: name
fields:
  hostname  None
  port      None
  path      []
  name      'name'
  tag       None
  digest    None
EOF

# one-component path
cat <<'EOF' | yolo path1/name 0
as string:    path1/name
for filename: path1%name
fields:
  hostname  None
  port      None
  path      ['path1']
  name      'name'
  tag       None
  digest    None
EOF

# two-component path
cat <<'EOF' | yolo path1/path2/name 0
as string:    path1/path2/name
for filename: path1%path2%name
fields:
  hostname  None
  port      None
  path      ['path1', 'path2']
  name      'name'
  tag       None
  digest    None
EOF

# host with dot
cat <<'EOF' | yolo example.com/name 0
as string:    example.com/name
for filename: example.com%name
fields:
  hostname  'example.com'
  port      None
  path      []
  name      'name'
  tag       None
  digest    None
EOF

# host with dot, with port
cat <<'EOF' | yolo example.com:8080/name 0
as string:    example.com:8080/name
for filename: example.com:8080%name
fields:
  hostname  'example.com'
  port      8080
  path      []
  name      'name'
  tag       None
  digest    None
EOF

# host without dot, with port
cat <<'EOF' | yolo examplecom:8080/name 0
as string:    examplecom:8080/name
for filename: examplecom:8080%name
fields:
  hostname  'examplecom'
  port      8080
  path      []
  name      'name'
  tag       None
  digest    None
EOF

# no path, tag
cat <<'EOF' | yolo name:tag 0
as string:    name:tag
for filename: name:tag
fields:
  hostname  None
  port      None
  path      []
  name      'name'
  tag       'tag'
  digest    None
EOF

# no path, digest
cat <<'EOF' | yolo name@sha256:feeddad 0
as string:    name@sha256:feeddad
for filename: name@sha256:feeddad
fields:
  hostname  None
  port      None
  path      []
  name      'name'
  tag       None
  digest    'feeddad'
EOF

# everything, tagged
cat <<'EOF' | yolo example.com:8080/path1/path2/name:tag 0
as string:    example.com:8080/path1/path2/name:tag
for filename: example.com:8080%path1%path2%name:tag
fields:
  hostname  'example.com'
  port      8080
  path      ['path1', 'path2']
  name      'name'
  tag       'tag'
  digest    None
EOF

# everything, tagged, filename component
cat <<'EOF' | yolo example.com:8080%path1%path2%name:tag 0
as string:    example.com:8080/path1/path2/name:tag
for filename: example.com:8080%path1%path2%name:tag
fields:
  hostname  'example.com'
  port      8080
  path      ['path1', 'path2']
  name      'name'
  tag       'tag'
  digest    None
EOF

# everything, digest
cat <<'EOF' | yolo example.com:8080/path1/path2/name@sha256:feeddad 0
as string:    example.com:8080/path1/path2/name@sha256:feeddad
for filename: example.com:8080%path1%path2%name@sha256:feeddad
fields:
  hostname  'example.com'
  port      8080
  path      ['path1', 'path2']
  name      'name'
  tag       None
  digest    'feeddad'
EOF

# errors

# invalid character in image name
cat <<'EOF' | yolo 'name*' 1
image ref syntax error, char 5: name*
EOF

# missing port number
cat <<'EOF' | yolo 'example.com:/path1/name' 1
image ref syntax error, char 13: example.com:/path1/name
EOF

# path with leading slash
cat <<'EOF' | yolo '/path1/name' 1
image ref syntax error, char 1: /path1/name
EOF

# path but no name
cat <<'EOF' | yolo 'path1/' 1
image ref syntax error, at end: path1/
EOF

# bad digest algorithm
cat <<'EOF' | yolo 'name@sha512:feeddad' 1
image ref syntax error, char 5: name@sha512:feeddad
EOF

# both tag and digest
cat <<'EOF' | yolo 'name:tag@sha512:feeddad' 1
image ref syntax error, char 9: name:tag@sha512:feeddad
EOF

echo 'ok'
