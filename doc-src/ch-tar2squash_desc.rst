Synopsis
========

::

  $ ch-tar2squash TARBALL OUTDIR [ARGS ...]

Description
===========

Create Charliecloud SquashFS file from :code:`TARBALL` 
in directory :code:`OUTDIR` with name matching :code:`TARBALL` 

Executes :code:`ch-tar2dir` and :code:`ch-dir2sqfs`

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ls -lh /tmp
  total 43M
  -rw-rw-r-- 1 charlie charlie 43M Apr 23 14:49 debian.tar.gz
  $ ch-tar2squash /tmp/debian.tar.gz /tmp
  Parallel mksquashfs: Using 6 processors
  Creating 4.0 filesystem on /tmp/debian.sqfs, block size 131072.
  [=========================================================================/] 5323/5323 100%

  .
  .
  .
  .
  squashed /tmp/debian.sqfs OK
  $ ls -lh /tmp
  total 83M
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:50 debian.sqfs
  -rw-rw-r-- 1 charlie charlie 43M Apr 23 14:49 debian.tar.gz