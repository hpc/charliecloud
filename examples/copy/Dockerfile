# Exercise the COPY instruction, which has rather strange semantics compared
# to what we are used to in cp(1). See FAQ.
#
# ch-test-scope: standard
# ch-test-builder-exclude: buildah
# ch-test-builder-exclude: buildah-runc
# ch-test-builder-exclude: buildah-setuid

FROM alpine:3.17

# Test directory
RUN mkdir /test
WORKDIR /test


## Source: Regular file(s)

# Source:  one file
# Dest:    new file, relative to workdir
COPY fileA file1a

# Source:  one file
# Dest:    new file, absolute path
COPY fileA /test/file1b

# Source:  one file, absolute path (root is context directory)
# Dest:    new file
COPY /fileB file2

# Source:  one file
# Dest:    existing file
RUN echo 'this should be overwritten' > file3
COPY fileA file3

# Source:  one file
# Dest:    symlink to existing file, relative path
RUN echo 'this should be overwritten' > file4 \
 && ln -s file4 symlink-to-file4
COPY fileA symlink-to-file4

# Source:  one file
# Dest:    symlink to existing file, absolute path
RUN echo 'this should be overwritten' > file5 \
 && ln -s /test/file5 symlink-to-file5
COPY fileA symlink-to-file5

# Source:  one file
# Dest:    existing directory, no trailing slash
#
# Note: This behavior is inconsistent with the Dockerfile reference, which
# implies that dir1a must be a file because it does not end in slash.
RUN mkdir dir01a
COPY fileA dir01a

# Source:  one file
# Dest:    existing directory, trailing slash
RUN mkdir dir01b
COPY fileA dir01b/

# Source:  one file
# Dest:    symlink to existing directory, relative, no trailing slash
RUN mkdir dir01c \
 && ln -s dir01c symlink-to-dir01c
COPY fileA symlink-to-dir01c

# Source:  one file
# Dest:    symlink to existing directory, absolute, no trailing slash
RUN mkdir dir01d \
 && ln -s /test/dir01d symlink-to-dir01d
COPY fileA symlink-to-dir01d

# Source:  one file
# Dest:    symlink to existing directory, relative, trailing slash
RUN mkdir dir01e \
 && ln -s dir01e symlink-to-dir01e
COPY fileA symlink-to-dir01e/

# Source:  one file
# Dest:    symlink to existing directory, absolute, trailing slash
RUN mkdir dir01f \
 && ln -s /test/dir01f symlink-to-dir01f
COPY fileA symlink-to-dir01f/

# Source:  one file
# Dest:    symlink to existing directory, multi-level, relative, no slash
RUN mkdir -p dir01g/dir \
 && ln -s dir01g symlink-to-dir01g
COPY fileA symlink-to-dir01g/dir

# Source:  one file
# Dest:    symlink to existing directory,  multi-level, absolute, no slash
RUN mkdir -p dir01h/dir \
 && ln -s /test/dir01h symlink-to-dir01h
COPY fileA symlink-to-dir01h/dir

# Source:  one file
# Dest:    new directory, one level of creation
COPY fileA dir02/

# Source:  one file
# Dest:    new directory, two levels of creation
COPY fileA dir03a/dir03b/

# Source:  two files, explicit
# Dest:    existing directory
RUN mkdir dir04
COPY fileA fileB dir04/

# Source:  two files, explicit
# Dest:    new directory, one level
COPY fileA fileB dir05/

# Source:  two files, wildcard
# Dest:    existing directory
RUN mkdir dir06
COPY file* dir06/


## Source: Director(y|ies)

# Source:  one directory
# Dest:    existing directory, no trailing slash
#
# Note: Again, the reference seems to imply this shouldn’t work.
RUN mkdir dir07a
COPY dirA dir07a

# Source:  one directory
# Dest:    existing directory, trailing slash
RUN mkdir dir07b
COPY dirA dir07b/

# Source:  one directory
# Dest:    symlink to existing directory, relative, no trailing slash
RUN mkdir dir07c \
 && ln -s dir07c symlink-to-dir07c
COPY dirA symlink-to-dir07c

# Source:  one directory
# Dest:    symlink to existing directory, absolute, no trailing slash
RUN mkdir dir07d \
 && ln -s /test/dir07d symlink-to-dir07d
COPY dirA symlink-to-dir07d

# Source:  one directory
# Dest:    symlink to existing directory, relative, trailing slash
RUN mkdir dir07e \
 && ln -s dir07e symlink-to-dir07e
COPY dirA symlink-to-dir07e/

# Source:  one directory
# Dest:    symlink to existing directory, absolute, trailing slash
RUN mkdir dir07f \
 && ln -s /test/dir07f symlink-to-dir07f
COPY dirA symlink-to-dir07f/

# Source:  one directory
# Dest:    new directory, one level, no trailing slash
#
# Note: Again, the reference seems to imply this shouldn’t work.
COPY dirA dir08a

# Source:  one directory
# Dest:    new directory, one level, trailing slash
COPY dirA dir08b/

# NOTE: Not currently tested (see #1707).
#
# # Source:  one directory
# # Dest:    existing file, 2nd level
# #
# # Note: While this fails if the existing file is at the top level (which we
# # verify in test/build/50_dockerfile.bats), if the existing file is at the 2nd
# # level, it's overwritten by the directory.
# RUN touch dir08a/dirCb
# COPY dirCa dir08a

# Source:  two directories, explicit
# Dest:    existing directory
RUN mkdir dir09
COPY dirA dirB dir09/

# Source:  two directories, explicit
# Dest:    new directory, one level
COPY dirA dirB dir10/

# Source:  two directories, wildcard
# Dest:    existing directory
RUN mkdir dir11
COPY dir[AB] dir11/

# Source:  two directories, wildcard
# Dest:    new directory, one level
COPY dir[AB] dir12/


## Source: Symlink(s)

# Note: Behavior for symlinks is not documented. See FAQ.

# Source:  one symbolic link, to file, named explicitly
# Dest:    existing directory
COPY symlink-to-fileA ./

# Source:  one symbolic link, to directory, named explicitly
# Dest:    existing directory
RUN mkdir dir13
COPY dirCa/symlink-to-dirCb dir13/

# Source:  one symbolic link, to file, in a directory
# Dest:    existing directory
RUN mkdir dir14
COPY dirD dir14/

# Source:  one symbolic link, to file, in a directory
# Dest:    new directory, one level
COPY dirD dir15/

# Source:  one symbolic link, to directory, in a directory
# Dest:    existing directory
RUN mkdir dir16
COPY dirEa dir16/

# Source:  two symbolic links, to files, named explicitly
# Dest:    existing directory
RUN mkdir dir17
COPY fileB symlink-to-fileB-A symlink-to-fileB-B dir17/

# Source:  two symbolic links, to files, wildcard
# Dest:    existing directory
RUN mkdir dir18
COPY fileB symlink-to-fileB-* dir18/


## Merge directory trees

# Set up destination directory tree.
RUN mkdir dir19 \
 && mkdir dir19/dir19a1 \
 && mkdir dir19/dir19a2 \
 && mkdir dir19/dir19a2/dir19b1 \
 && mkdir dir19/dir19a2/dir19b2 \
 && echo old > dir19/file19a1 \
 && echo old > dir19/file19a2 \
 && echo old > dir19/dir19a1/file19b1 \
 && echo old > dir19/dir19a2/file19b1 \
 && echo old > dir19/dir19a2/file19b2 \
 && echo old > dir19/dir19a2/dir19b2/file19c1 \
 && chmod 777 dir19/dir19a2

# Copy in the new directory tree. This is supposed to merge the two trees.
# Important considerations, from perspective of destination tree:
#
#   1. File at top level, new.
#   2. File at top level, existing (should overwrite).
#   3. File at 2nd level, new.
#   4. File at 2nd level, existing (should overwrite).
#   5. Directory at top level, new.
#   6. Directory at top level, existing (permissions should overwrite).
#   7. Directory at 2nd level, new.
#   8. Directory at 2nd level, existing (permissions should overwrite).
#
# The directories should be o-rwx so we can see if the permissions were from
# the old or new version.
RUN test $(stat -c '%A' dir19/dir19a2 | cut -c8-) = 'rwx' \
 && stat -c '%n: %A' dir19/dir19a2
COPY dirF dir19/
RUN test $(stat -c '%A' dir19/dir19a2 | cut -c8-) != 'rwx' \
 && stat -c '%n: %A' dir19/dir19a2


## Destination: Symlink, 2nd level.

# NOTE: Not currently tested (see #1707).
#
# # Note: This behavior is DIFFERENT from the symlink at 1st level tests above
# # (recall we are trying to be bug-compatible with Docker).
#
# # Set up destination.
# RUN mkdir dir20 \
#  && echo new > dir20/filex \
#  && mkdir dir20/dirx \
#  && for i in $(seq 4); do \
#            echo file$i > dir20/file$i \
#         && ln -s file$i dir20/s_file$i \
#         && mkdir dir20/dir$i \
#         && echo dir$i/file_ > dir20/dir$i/file_ \
#         && ln -s dir$i dir20/s_dir$i; \
#     done \
#  && ls -lR dir20
#
# # Copy in the new directory tree. In all of these cases, the source simply
# # overwrites the destination; symlinks are not followed.
# #
# #      name     source        destination
# #      -------  ------------  ------------
# #   1. s_file1  file          link to file
# #   2. s_dir1   file          link to dir
# #   3. s_file2  link to file  link to file
# #   4. s_dir2   link to file  link to dir
# #   5. s_file3  link to dir   link to file
# #   6. s_dir3   link to dir   link to dir
# #   7. s_file4  directory     link to file
# #   8. s_dir4   directory     link to dir
# #
# COPY dirG dir20/


## Wrap up; this output helps to build the expectations in test.bats.

# Need GNU find, not BusyBox find
RUN apk add --no-cache findutils

# File tree with type annotation characters.
RUN ls -1FR .

# Regular file contents.
RUN find . -type f -printf '%y: %p: ' -a -exec cat {} \; | sort

# Symlink targets.
RUN find . -type l -printf '%y: %p -> %l\n' | sort
