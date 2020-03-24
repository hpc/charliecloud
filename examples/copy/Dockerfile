# Exercise the COPY instruction, which has rather strange semantics compared
# to what we are used to in cp(1). The main, but not only, weirdness is that
# directories are expanded rather than copied as a directory.
#
# See: https://docs.docker.com/engine/reference/builder/#copy
#
# ch-test-scope: standard

FROM alpine:3.9

## Setup

# Test directory
RUN mkdir /test
WORKDIR /test

# Need GNU find, not BusyBox find
RUN apk add --no-cache findutils


## Source: Regular file(s)

# Source:  one file
# Dest:    file
COPY fileA file1

# Source:  one file, absolute path (root is context directory)
# Dest:    file
COPY /fileB file2

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
# Note: Again, the reference seems to imply this shouldn't work.
RUN mkdir dir07a
COPY dirA dir07a

# Source:  one directory
# Dest:    existing directory, trailing slash
RUN mkdir dir07b
COPY dirA dir07b/

# Source:  one directory
# Dest:    new directory, one level, no trailing slash
#
# Note: Again, the reference seems to imply this shouldn't work.
COPY dirA dir08a

# Source:  one directory
# Dest:    new directory, one level, trailing slash
COPY dirA dir08b/

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


## Wrap up; this output helps to build the expectations in test.bats.

# File tree with type annotation characters.
RUN ls -1FR .

# Regular file contents.
RUN find . -type f -printf '%y: %p: ' -a -exec cat {} \; | sort

# Symlink targets.
RUN find . -type l -printf '%y: %p -> %l\n' | sort
