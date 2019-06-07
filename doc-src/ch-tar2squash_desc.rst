Synopsis
========

::

  $ ch-tar2squash TARBALL OUTDIR [ARGS ...]

Description
===========

Create Charliecloud SquashFS file from :code:`TARBALL` in directory
:code:`OUTDIR`, named as :code:`TARBALL` with extension :code:`.sqfs`.

Wrapper for :code:`ch-tar2dir` and :code:`ch-dir2sqfs`.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ch-tar2squash /var/tmp/debian.tar.gz /var/tmp
  Parallel mksquashfs: Using 6 processors
  Creating 4.0 filesystem on /var/tmp/debian.sqfs, block size 131072.
  [...]
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:50 debian.sqfs
  $ ls -lh /var/tmp/debian*
  total 83M
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:50 debian.sqfs
  -rw-rw-r-- 1 charlie charlie 43M Apr 23 14:49 debian.tar.gz
