load ../common

# Testing strategy overview:
#
# The most efficient way to test conversion through all formats would be to
# start with a directory, cycle through all the formats one at a time, with
# directory being last, then compare the starting and ending directories. That
# corresponds to visiting all the cells in the matrix below, starting from one
# labeled "a", ending in one labeled "b", and skipping those labeled with a
# dash. Also, if visit n is in column i, then the next visit n+1 must be in
# row i. This approach does each conversion exactly once.
#
#               output ->
#               | dir      | ch-image | docker   | squash   | tar     |
# input         +----------+----------+----------+----------+---------+
#   |  dir      |    —     |    a     |    a     |    a     |    a    |
#   v  ch-image |    b     |    —     |          |          |         |
#      docker   |    b     |          |    —     |          |         |
#      squash   |    b     |          |          |    —     |         |
#      tar      |    b     |          |          |          |    —    |
#               +----------+----------+----------+----------+---------+
#
# Because we start with a directory already available, this yields 5*5 - 5 - 1
# = 19 conversions. However, I was not able to figure out a traversal order
# that would meet the constraints.
#
# Thus, we use the following algorithm.
#
#   for every format i except dir:         (4 iterations)
#     convert start_dir -> i
#     for every format j except dir:       (4)
#          if i≠j: convert i -> j
#          convert j -> finish_dir
#          compare start_dir with finish_dir
#
# This yields 4 * (3*2 + 1*1) = 28 conversions, due to excess conversions to
# dir. However, it can better isolate where the conversion went wrong, because
# the chain is 3 conversions long rather than 19.
#
# The outer loop is unrolled into four separate tests to avoid having one test
# that runs for two minutes.


# This is a little goofy, because several of the texts need *all* the
# builders. Thus, we (a) run only for builder ch-image but (b)
# pedantic-require Docker to also be installed.
setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
    [[ $CH_TEST_PACK_FMT = *-unpack ]] || skip 'needs directory images'
    if ! command -v docker > /dev/null 2>&1; then
        pedantic_fail 'docker not found'
    fi
}


# Return success if directories $1 and $2 are recursively the same, failure
# otherwise. This compares only metadata. False positives are possible if a
# file's content changes but the size and all other metadata stays the same;
# this seems unlikely. We could also use "diff -qr --no-dereference", which
# would also compare file conttent, but diff's --exclude only accepts basename
# patterns, not paths. The long list of excludes is things that don't
# round-trip through the various formats; the surprising directories (e.g.
# /dev) are because modification times seem to change.
compare () {
    out=$(  rsync -nv -aAX --delete "${1}/" "$2" \
          | sed -E -e '/^$/d' \
                   -e '/^sending incremental file list/d' \
                   -e '/^sent [0-9,]+ bytes/d' \
                   -e '/^total size is/d' \
                   -e '\|^deleting ch/|d' \
                   -e '\|^deleting .dockerenv$|d' \
                   -e '\|^deleting dev/console$|d' \
                   -e '\|^deleting dev/pts/$|d' \
                   -e '\|^deleting dev/shm/$|d' \
                   -e '\|^./$|d' \
                   -e '\|^WEIRD_AL_YANKOVIC$|d' \
                   -e '\|^dev/$|d' \
                   -e '\|^etc/$|d' \
                   -e '\|^etc/hostname$|d' \
                   -e '\|^etc/hosts$|d' \
                   -e '\|^etc/resolv.conf -> /etc/resolv.conf.real$|d' \
                   -e '\|^mnt/dev/dontdeleteme$|d' )
    echo "$out"
    [ -z "$out" ]
}

# Kludge to cook up the right input and output descriptors for ch-convert.
convert () {
    ct=$1
    in_fmt=$2
    out_fmt=$3;
    case $in_fmt in
        ch-image)
            in_desc=tmpimg
            ;;
        dir)
            in_desc=$ch_timg
            ;;
        docker)
            in_desc=tmpimg
            ;;
        tar)
            in_desc=${BATS_TMPDIR}/convert.tar.gz
            ;;
        squash)
            in_desc=${BATS_TMPDIR}/convert.sqfs
            ;;
        *)
            echo "unknown input format: $in_fmt"
            false
            ;;
    esac
    case $out_fmt in
        ch-image)
            out_desc=tmpimg
            ;;
        dir)
            out_desc=${BATS_TMPDIR}/convert.dir
            ;;
        docker)
            out_desc=tmpimg
            ;;
        tar)
            out_desc=${BATS_TMPDIR}/convert.tar.gz
            ;;
        squash)
            out_desc=${BATS_TMPDIR}/convert.sqfs
            ;;
        *)
            echo "unknown output format: $out_fmt"
            false
            ;;
    esac
    echo "CONVERT ${ct}: ${in_desc} ($in_fmt) -> ${out_desc} (${out_fmt})"
    delete "$out_fmt" "$out_desc"
    ch-convert --no-clobber -v -i "$in_fmt" -o "$out_fmt" "$in_desc" "$out_desc"
    # Doing it twice doubles the time but also tests that both new conversions
    # and overwrite work. Hence, full scope only.
    if [[ $CH_TEST_SCOPE = full ]]; then
        ch-convert -v -i "$in_fmt" -o "$out_fmt" "$in_desc" "$out_desc"
    fi
}

delete () {
    fmt=$1
    desc=$2
    case $fmt in
        ch-image)
            ch-image delete "$desc" || true
            ;;
        dir)
            rm -Rf --one-file-system "$desc"
            ;;
        docker)
            docker_ rmi -f "$desc"
            ;;
        tar)
            rm -f "$desc"
            ;;
        squash)
            rm -f "$desc"
            ;;
        *)
            echo "unknown format: $fmt"
            false
            ;;
    esac
}

# Test conversions dir -> $1 -> (all) -> dir.
test_from () {
    end=${BATS_TMPDIR}/convert.dir
    ct=1
    convert "$ct" dir "$1"
    for j in ch-image docker squash tar; do
        if [[ $1 != "$j" ]]; then
            ct=$((ct+1))
            convert "$ct" "$1" "$j"
        fi
        ct=$((ct+1))
        convert "$ct" "$1" dir
        image_ok "$end"
        compare "$ch_timg" "$end"
    done
}


@test 'ch-convert: format inference' {
    # Test input only; output uses same code. Test cases match all the
    # criteria to validate the priority. We don't exercise every possible
    # descriptor pattern, only those I thought had potential for error.

    # SquashFS
    run ch-convert -n ./foo:bar.sqfs out.tar
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   squash'* ]]

    # tar
    run ch-convert -n ./foo:bar.tar out.sqfs
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   tar'* ]]
    run ch-convert -n ./foo:bar.tgz out.sqfs
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   tar'* ]]
    run ch-convert -n ./foo:bar.tar.Z out.sqfs
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   tar'* ]]
    run ch-convert -n ./foo:bar.tar.gz out.sqfs
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   tar'* ]]

    # directory
    run ch-convert -n ./foo:bar out.tar
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'input:   dir'* ]]

    # builders
    run ch-convert -n foo out.tar
    echo "$output"
    if command -v ch-image > /dev/null 2>&1; then
        [[ $status -eq 0 ]]
        [[ $output = *'input:   ch-image'* ]]
    elif command -v docker > /dev/null 2>&1; then
        [[ $status -eq 0 ]]
        [[ $output = *'input:   docker'* ]]
    else
        [[ $status -eq 1 ]]
        [[ $output = *'no builder found' ]]
    fi
}


@test 'ch-convert: errors' {
    # same format
    run ch-convert -n foo.tar foo.tar.gz
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: input and output formats must be different'* ]]

    # output directory not an image
    touch "${BATS_TMPDIR}/foo.tar"
    run ch-convert "${BATS_TMPDIR}/foo.tar" "$BATS_TMPDIR"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: exists but does not appear to be an image: ${BATS_TMPDIR}"* ]]
    rm "${BATS_TMPDIR}/foo.tar"
}


@test 'ch-convert: --no-clobber' {
    # ch-image
    printf 'FROM alpine:3.9\n' | ch-image build -t tmpimg -f - "$BATS_TMPDIR"
    run ch-convert --no-clobber -o ch-image "$BATS_TMPDIR" tmpimg
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: exists in ch-image storage, not deleting per --no-clobber: tmpimg" ]]

    # dir
    ch-convert -i ch-image -o dir 00_tiny "$BATS_TMPDIR"/00_tiny
    run ch-convert --no-clobber -i ch-image -o dir 00_tiny "$BATS_TMPDIR"/00_tiny
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: exists, not deleting per --no-clobber: ${BATS_TMPDIR}/00_tiny" ]]
    rm -Rf --one-file-system "$BATS_TMPDIR"/00_tiny

    # docker
    printf 'FROM alpine:3.9\n' | docker_ build -t tmpimg -
    run ch-convert --no-clobber -o docker "$BATS_TMPDIR" tmpimg
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: exists in Docker storage, not deleting per --no-clobber: tmpimg" ]]

    # squash
    touch "${BATS_TMPDIR}/00_tiny.sqfs"
    run ch-convert --no-clobber -i ch-image -o squash 00_tiny "$BATS_TMPDIR"/00_tiny.sqfs
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: exists, not deleting per --no-clobber: ${BATS_TMPDIR}/00_tiny.sqfs" ]]
    rm "${BATS_TMPDIR}/00_tiny.sqfs"

    # tar
    touch "${BATS_TMPDIR}/00_tiny.tar.gz"
    run ch-convert --no-clobber -i ch-image -o tar 00_tiny "$BATS_TMPDIR"/00_tiny.tar.gz
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: exists, not deleting per --no-clobber: ${BATS_TMPDIR}/00_tiny.tar.gz" ]]
    rm "${BATS_TMPDIR}/00_tiny.tar.gz"
}


@test 'ch-convert: pathological tarballs' {
    [[ $CH_PACK_FMT = tar ]] || skip 'tar mode only'
    out=${BATS_TMPDIR}/convert.dir
    # Are /dev fixtures present in tarball? (issue #157)
    present=$(tar tf "$ch_ttar" | grep -F deleteme)
    [[ $(echo "$present" | wc -l) -eq 4 ]]
    echo "$present" | grep -E '^img/dev/deleteme$'
    echo "$present" | grep -E '^./dev/deleteme$'
    echo "$present" | grep -E '^dev/deleteme$'
    echo "$present" | grep -E '^img/mnt/dev/dontdeleteme$'
    # Convert to dir.
    ch-convert "$ch_ttar" "$out"
    image_ok "$out"
    # Did we raise hidden files correctly?
    [[ -e ${out}/.hiddenfile1 ]]
    [[ -e ${out}/..hiddenfile2 ]]
    [[ -e ${out}/...hiddenfile3 ]]
    # Did we remove the right /dev stuff?
    [[ -e ${out}/mnt/dev/dontdeleteme ]]
    [[ $(ls -Aq "${out}/dev") -eq 0 ]]
    ch-run "$out" -- test -e /mnt/dev/dontdeleteme
}


@test 'ch-convert: dir -> ch-image -> X' {
    test_from ch-image
}

@test 'ch-convert: dir -> docker -> X' {
    test_from docker
}

@test 'ch-convert: dir -> squash -> X' {
    test_from squash
}

@test 'ch-convert: dir -> tar -> X' {
    test_from tar
}
