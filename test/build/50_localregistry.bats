load ../common
tag='ch-image push'

# Note: These tests use a local registry listening on localhost:5000 but do
# not start it. Therefore, they do not depend on whether the pushed images are
# already present.


setup () {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'
    localregistry_init
}

@test "${tag}: without destination reference" {
    # FIXME: This test copies an image manually so we can use it to push.
    # Remove when we have real aliasing support for images.
    ch-image build -t localhost:5000/alpine:3.17 - <<'EOF'
FROM alpine:3.17
EOF

    run ch-image -v --tls-no-verify push localhost:5000/alpine:3.17
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'pushing image:   localhost:5000/alpine:3.17'* ]]
    [[ $output = *"image path:      ${CH_IMAGE_STORAGE}/img/localhost+5000%alpine+3.17"* ]]

    ch-image delete localhost:5000/alpine:3.17
}

@test "${tag}: without metadata history" {
    ch-image build -t tmpimg - <<'EOF'
FROM alpine:3.17
EOF

    ch-convert tmpimg "$BATS_TMPDIR/tmpimg"
    rm -rf "$BATS_TMPDIR/tmpimg/ch"

    ch-image delete tmpimg
    ch-image import "$BATS_TMPDIR/tmpimg" tmpimg

    run ch-image -v --tls-no-verify push tmpimg localhost:5000/tmpimg
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'pushing image:   tmpimg'* ]]
    [[ $output = *'destination:     localhost:5000/tmpimg'* ]]
    [[ $output = *"image path:      ${CH_IMAGE_STORAGE}/img/localhost+5000%tmpimg"* ]]
}

@test "${tag}: with destination reference" {
    run ch-image -v --tls-no-verify push alpine:3.17 localhost:5000/alpine:3.17
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'pushing image:   alpine:3.17'* ]]
    [[ $output = *'destination:     localhost:5000/alpine:3.17'* ]]
    [[ $output = *"image path:      ${CH_IMAGE_STORAGE}/img/alpine+3.17"* ]]
    # FIXME: Can’t re-use layer from previous test because it’s a copy.
    #re='layer 1/1: [0-9a-f]{7}: already present'
    #[[ $output =~ $re ]]
}

@test "${tag}: with --image" {
    # NOTE: This also tests round-tripping and a more complex destination ref.

    img="$BATS_TMPDIR"/pushtest-up
    img2="$BATS_TMPDIR"/pushtest-down
    mkdir -p "$img" "$img"/{bin,dev,usr}

    # Set up setuid/setgid files and directories.
    touch "$img"/{setuid_file,setgid_file}
    chmod 4640 "$img"/setuid_file
    chmod 2640 "$img"/setgid_file
    mkdir -p "$img"/{setuid_dir,setgid_dir}
    chmod 4750 "$img"/setuid_dir
    chmod 2750 "$img"/setgid_dir
    ls -l "$img"
    [[ $(stat -c '%A' "$img"/setuid_file) = -rwSr----- ]]
    [[ $(stat -c '%A' "$img"/setgid_file) = -rw-r-S--- ]]
    [[ $(stat -c '%A' "$img"/setuid_dir) =  drwsr-x--- ]]
    [[ $(stat -c '%A' "$img"/setgid_dir) =  drwxr-s--- ]]

    # Create fake history.
    mkdir -p "$img"/ch
    cat <<'EOF' > "$img"/ch/metadata.json
{
   "history": [ {"created_by": "ch-test" } ]
}
EOF

    # Push the image
    run ch-image -v --tls-no-verify push --image "$img" \
                                         localhost:5000/foo/bar:weirdal
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'pushing image:   localhost:5000/foo/bar:weirdal'* ]]
    [[ $output = *"image path:      ${img}"* ]]
    [[ $output = *'stripping unsafe setgid bit: ./setgid_dir'* ]]
    [[ $output = *'stripping unsafe setgid bit: ./setgid_file'* ]]
    [[ $output = *'stripping unsafe setuid bit: ./setuid_dir'* ]]
    [[ $output = *'stripping unsafe setuid bit: ./setuid_file'* ]]

    # Pull it back
    ch-image -v --tls-no-verify pull localhost:5000/foo/bar:weirdal
    ch-convert localhost:5000/foo/bar:weirdal "$img2"
    ls -l "$img2"
    [[ $(stat -c '%A' "$img2"/setuid_file) = -rw-r----- ]]
    [[ $(stat -c '%A' "$img2"/setgid_file) = -rw-r----- ]]
    [[ $(stat -c '%A' "$img2"/setuid_dir) =  drwxr-x--- ]]
    [[ $(stat -c '%A' "$img2"/setgid_dir) =  drwxr-x--- ]]
}

@test "${tag}: consistent layer hash" {
    run ch-image push --tls-no-verify alpine:3.17 localhost:5000/alpine:3.17
    echo "$output"
    [[ $status -eq 0 ]]
    push1=$(echo "$output" | grep -E 'layer 1/1: .+: checking')

    run ch-image push --tls-no-verify alpine:3.17 localhost:5000/alpine:3.17
    echo "$output"
    [[ $status -eq 0 ]]
    push2=$(echo "$output" | grep -E 'layer 1/1: .+: checking')

    diff -u <(echo "$push1") <(echo "$push2")
}

@test "${tag}: environment variables round-trip" {
    cat <<'EOF' | ch-image build -t tmpimg -
FROM alpine:3.17
ENV weird="al yankovic"
EOF

    ch-image push --tls-no-verify tmpimg localhost:5000/tmpimg
    ch-image pull --tls-no-verify localhost:5000/tmpimg
    ch-convert localhost:5000/tmpimg "$BATS_TMPDIR"/tmpimg

    run ch-run "$BATS_TMPDIR"/tmpimg --unset-env='*' --set-env -- env
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'weird=al yankovic'* ]]
}
