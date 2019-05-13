Synopsis
========

::

  $ ch-docker2squash IMAGE OUTDIR [ARGS ...]

Description
===========

Flattens the Docker image tagged :code:`IMAGE` into a Charliecloud squashfs in
directory :code:`OUTDIR`.

Executes :code:`ch-docker2tar` with :code:`--nocompress`, then :code:`ch-tar2sqfs`

Intermediate files and directories are removed.

Sudo privileges are required to run :code:`docker export`.

Optional :code:`ARGS` will be passed to :code:`mksquashfs`

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ls -lh /tmp
  total 0
  $ docker image list
  REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
  debian              stretch             2d337f242f07        3 weeks ago         101MB
  Parallel mksquashfs: Using 6 processors
  Creating 4.0 filesystem on /tmp/debian.sqfs, block size 131072.
  [=============================================================-] 5323/5323 100%

  Exportable Squashfs 4.0 filesystem, gzip compressed, data block size 131072
    compressed data, compressed metadata, compressed fragments, compressed xattrs
    duplicates are removed
  Filesystem size 41307.18 Kbytes (40.34 Mbytes)
    41.88% of uncompressed filesystem size (98640.27 Kbytes)
  Inode table size 69448 bytes (67.82 Kbytes)
    29.44% of uncompressed inode table size (235933 bytes)
  Directory table size 62787 bytes (61.32 Kbytes)
    47.08% of uncompressed directory table size (133364 bytes)
  Number of duplicate files found 174
  Number of inodes 7023
  Number of files 5014
  Number of fragments 440
  Number of symbolic links  1278
  Number of device nodes 0
  Number of fifo nodes 0
  Number of socket nodes 0
  Number of directories 731
  Number of ids (unique uids + gids) 1
  Number of uids 1
    charlie (1000)
  Number of gids 1
    charlie (1000)
  squashed /tmp/debian.sqfs OK
  $ ls -lh /tmp
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:37 debian.sqfs