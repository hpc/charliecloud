true
# shellcheck disable=SC2034
CH_TEST_TAG=$ch_test_tag

load "${CHTEST_DIR}/common.bash"

@test "${ch_tag}/ls" {
    scope standard
    prerequisites_ok copy

    # “ls -F” trailing symbol list: https://unix.stackexchange.com/a/82358
    diff -u - <(ch-run --cd /test "$ch_img" -- ls -1FR .) <<EOF
.:
dir01a/
dir01b/
dir01c/
dir01d/
dir01e/
dir01f/
dir01g/
dir01h/
dir02/
dir03a/
dir04/
dir05/
dir06/
dir07a/
dir07b/
dir07c/
dir07d/
dir07e/
dir07f/
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
dir19/
dir20/
file1a
file1b
file2
file3
file4
file5
symlink-to-dir01c@
symlink-to-dir01d@
symlink-to-dir01e@
symlink-to-dir01f@
symlink-to-dir01g@
symlink-to-dir01h@
symlink-to-dir07c@
symlink-to-dir07d@
symlink-to-dir07e@
symlink-to-dir07f@
symlink-to-file4@
symlink-to-file5@
symlink-to-fileA

./dir01a:
fileA

./dir01b:
fileA

./dir01c:
fileA

./dir01d:
fileA

./dir01e:
fileA

./dir01f:
fileA

./dir01g:
dir/

./dir01g/dir:
fileA

./dir01h:
dir/

./dir01h/dir:
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

./dir07c:
fileAa

./dir07d:
fileAa

./dir07e:
fileAa

./dir07f:
fileAa

./dir08a:
dirCb/
fileAa
symlink-to-dirCb@

./dir08a/dirCb:
fileCba
fileCbb

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

./dir19:
dir19a1/
dir19a2/
dir19a3/
file19a1
file19a2
file19a3

./dir19/dir19a1:
file19b1

./dir19/dir19a2:
dir19b1/
dir19b2/
dir19b3/
file19b1
file19b2
file19b3

./dir19/dir19a2/dir19b1:

./dir19/dir19a2/dir19b2:
file19c1

./dir19/dir19a2/dir19b3:
file19c1

./dir19/dir19a3:
file19b1

./dir20:
dir1/
dir2/
dir3/
dir4/
dirx/
diry/
file1
file2
file3
file4
filex
filey
s_dir1
s_dir2@
s_dir3@
s_dir4/
s_file1
s_file2@
s_file3@
s_file4/

./dir20/dir1:
file_

./dir20/dir2:
file_

./dir20/dir3:
file_

./dir20/dir4:
file_

./dir20/dirx:

./dir20/diry:
file_

./dir20/s_dir4:
file_

./dir20/s_file4:
file_
EOF
}

@test "${ch_tag}/content of regular files" {
    scope standard
    prerequisites_ok copy

    diff -u - <(ch-run --cd /test "$ch_img" \
                --   find . -type f -printf '%y: %p: ' -a -exec cat {} \; \
                   | sort) <<EOF
f: ./dir01a/fileA: fileA
f: ./dir01b/fileA: fileA
f: ./dir01c/fileA: fileA
f: ./dir01d/fileA: fileA
f: ./dir01e/fileA: fileA
f: ./dir01f/fileA: fileA
f: ./dir01g/dir/fileA: fileA
f: ./dir01h/dir/fileA: fileA
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
f: ./dir07c/fileAa: dirA/fileAa
f: ./dir07d/fileAa: dirA/fileAa
f: ./dir07e/fileAa: dirA/fileAa
f: ./dir07f/fileAa: dirA/fileAa
f: ./dir08a/dirCb/fileCba: dirCa/dirCb/fileCba
f: ./dir08a/dirCb/fileCbb: dirCa/dirCb/fileCbb
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
f: ./dir19/dir19a1/file19b1: old
f: ./dir19/dir19a2/dir19b2/file19c1: new
f: ./dir19/dir19a2/dir19b3/file19c1: new
f: ./dir19/dir19a2/file19b1: old
f: ./dir19/dir19a2/file19b2: new
f: ./dir19/dir19a2/file19b3: new
f: ./dir19/dir19a3/file19b1: new
f: ./dir19/file19a1: old
f: ./dir19/file19a2: new
f: ./dir19/file19a3: new
f: ./dir20/dir1/file_: dir1/file_
f: ./dir20/dir2/file_: dir2/file_
f: ./dir20/dir3/file_: dir3/file_
f: ./dir20/dir4/file_: dir4/file_
f: ./dir20/diry/file_: diry/file_
f: ./dir20/file1: file1
f: ./dir20/file2: file2
f: ./dir20/file3: file3
f: ./dir20/file4: file4
f: ./dir20/filex: new
f: ./dir20/filey: new
f: ./dir20/s_dir1: new
f: ./dir20/s_dir4/file_: s_dir4/file_
f: ./dir20/s_file1: new
f: ./dir20/s_file4/file_: s_file4/file_
f: ./file1a: fileA
f: ./file1b: fileA
f: ./file2: fileB
f: ./file3: fileA
f: ./file4: fileA
f: ./file5: fileA
f: ./symlink-to-fileA: fileA
EOF
}

@test "${ch_tag}/symlink targets" {
    scope standard
    prerequisites_ok copy

    diff -u - <(ch-run --cd /test "$ch_img" \
                -- find . -type l -printf '%y: %p -> %l\n' | sort) <<EOF
l: ./dir08a/symlink-to-dirCb -> dirCb
l: ./dir14/symlink-to-fileDa -> fileDa
l: ./dir15/symlink-to-fileDa -> fileDa
l: ./dir16/symlink-to-dirEb -> dirEb
l: ./dir20/s_dir2 -> filey
l: ./dir20/s_dir3 -> diry
l: ./dir20/s_file2 -> filey
l: ./dir20/s_file3 -> diry
l: ./symlink-to-dir01c -> dir01c
l: ./symlink-to-dir01d -> /test/dir01d
l: ./symlink-to-dir01e -> dir01e
l: ./symlink-to-dir01f -> /test/dir01f
l: ./symlink-to-dir01g -> dir01g
l: ./symlink-to-dir01h -> /test/dir01h
l: ./symlink-to-dir07c -> dir07c
l: ./symlink-to-dir07d -> /test/dir07d
l: ./symlink-to-dir07e -> dir07e
l: ./symlink-to-dir07f -> /test/dir07f
l: ./symlink-to-file4 -> file4
l: ./symlink-to-file5 -> /test/file5
EOF
}
