true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

@test 'file structure' {
    scope standard
    prerequisites_ok copy

    # "ls -F" trailing symbol list: https://unix.stackexchange.com/a/82358
    diff -u - <(ch-run "$ch_img" -- ls -FR /test) <<EOF
/test:
dir01a/
dir01b/
dir02/
dir03a/
dir04/
dir05/
dir06/
dir07a/
dir07b/
dir08a/
dir08b/
dir09/
dir10/
dir11/
dir12/
file1
file2

/test/dir01a:
fileA

/test/dir01b:
fileA

/test/dir02:
fileA

/test/dir03a:
dir03b/

/test/dir03a/dir03b:
fileA

/test/dir04:
fileA
fileB

/test/dir05:
fileA
fileB

/test/dir06:
fileA
fileB

/test/dir07a:
fileAa

/test/dir07b:
fileAa

/test/dir08a:
fileAa

/test/dir08b:
fileAa

/test/dir09:
fileAa
fileBa
fileBb

/test/dir10:
fileAa
fileBa
fileBb

/test/dir11:
fileAa
fileBa
fileBb

/test/dir12:
fileAa
fileBa
fileBb
EOF
}
