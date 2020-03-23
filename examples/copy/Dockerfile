# Exercise the COPY instruction, which has rather strange semantics compared
# to what we are used to in cp(1). The main, but not only, weirdness is that
# directories are expanded rather than copied as a directory.
#
# See: https://docs.docker.com/engine/reference/builder/#copy
#
# ch-test-scope: standard

FROM 00_tiny

RUN mkdir /test
WORKDIR /test

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
COPY dir* dir11/

# Source:  two directories, wildcard
# Dest:    existing directory
COPY dir* dir12/

# Print status for comparison in test.bats.
RUN ls -FR /test
