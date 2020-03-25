true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

@test 'ls' {
    scope standard
    prerequisites_ok copy

    # "ls -F" trailing symbol list: https://unix.stackexchange.com/a/82358
    diff -u - <(ch-run --cd /test "$ch_img" -- ls -1FR .) <<EOF
.:
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
dir13/
dir14/
dir15/
dir16/
dir17/
dir18/
file1
file2
file3
symlink-to-fileA

./dir01a:
fileA

./dir01b:
fileA

./dir02:
fileA

./dir03a:
dir03b/

./dir03a/dir03b:
fileA

./dir04:
fileA
fileB

./dir05:
fileA
fileB

./dir06:
fileA
fileB

./dir07a:
fileAa

./dir07b:
fileAa

./dir08a:
fileAa

./dir08b:
fileAa

./dir09:
fileAa
fileBa
fileBb

./dir10:
fileAa
fileBa
fileBb

./dir11:
fileAa
fileBa
fileBb

./dir12:
fileAa
fileBa
fileBb

./dir13:
fileCba
fileCbb

./dir14:
fileDa
symlink-to-fileDa@

./dir15:
fileDa
symlink-to-fileDa@

./dir16:
dirEb/
symlink-to-dirEb@

./dir16/dirEb:
fileEba
fileEbb

./dir17:
fileB
symlink-to-fileB-A
symlink-to-fileB-B

./dir18:
fileB
symlink-to-fileB-A
symlink-to-fileB-B
EOF
}

@test 'content of regular files' {
    scope standard
    prerequisites_ok copy

    diff -u - <(ch-run --cd /test "$ch_img" \
                --   find . -type f -printf '%y: %p: ' -a -exec cat {} \; \
                   | sort) <<EOF
f: ./dir01a/fileA: fileA
f: ./dir01b/fileA: fileA
f: ./dir02/fileA: fileA
f: ./dir03a/dir03b/fileA: fileA
f: ./dir04/fileA: fileA
f: ./dir04/fileB: fileB
f: ./dir05/fileA: fileA
f: ./dir05/fileB: fileB
f: ./dir06/fileA: fileA
f: ./dir06/fileB: fileB
f: ./dir07a/fileAa: dirA/fileAa
f: ./dir07b/fileAa: dirA/fileAa
f: ./dir08a/fileAa: dirA/fileAa
f: ./dir08b/fileAa: dirA/fileAa
f: ./dir09/fileAa: dirA/fileAa
f: ./dir09/fileBa: dirB/fileBa
f: ./dir09/fileBb: dirB/fileBb
f: ./dir10/fileAa: dirA/fileAa
f: ./dir10/fileBa: dirB/fileBa
f: ./dir10/fileBb: dirB/fileBb
f: ./dir11/fileAa: dirA/fileAa
f: ./dir11/fileBa: dirB/fileBa
f: ./dir11/fileBb: dirB/fileBb
f: ./dir12/fileAa: dirA/fileAa
f: ./dir12/fileBa: dirB/fileBa
f: ./dir12/fileBb: dirB/fileBb
f: ./dir13/fileCba: dirCa/dirCb/fileCba
f: ./dir13/fileCbb: dirCa/dirCb/fileCbb
f: ./dir14/fileDa: dirD/fileDa
f: ./dir15/fileDa: dirD/fileDa
f: ./dir16/dirEb/fileEba: dirEa/dirEb/fileEba
f: ./dir16/dirEb/fileEbb: dirEa/dirEb/fileEbb
f: ./dir17/fileB: fileB
f: ./dir17/symlink-to-fileB-A: fileB
f: ./dir17/symlink-to-fileB-B: fileB
f: ./dir18/fileB: fileB
f: ./dir18/symlink-to-fileB-A: fileB
f: ./dir18/symlink-to-fileB-B: fileB
f: ./file1: fileA
f: ./file2: fileB
f: ./file3: fileA
f: ./symlink-to-fileA: fileA
EOF
}

@test 'symlink targets' {
    scope standard
    prerequisites_ok copy

    # "ls -F" trailing symbol list: https://unix.stackexchange.com/a/82358
    diff -u - <(ch-run --cd /test "$ch_img" \
                -- find . -type l -printf '%y: %p -> %l\n' | sort) <<EOF
l: ./dir14/symlink-to-fileDa -> fileDa
l: ./dir15/symlink-to-fileDa -> fileDa
l: ./dir16/symlink-to-dirEb -> dirEb
EOF
}
