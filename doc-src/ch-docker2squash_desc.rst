Synopsis
========

::

  $ ch-docker2squash IMAGE OUTDIR [ARGS ...]

Description
===========

Flattens the Docker image tagged :code:`IMAGE` into a SquashFS file in
:code:`OUTDIR`.

Wrapper for :code:`ch-docker2tar --nocompress` and :code:`ch-tar2sqfs`.
Intermediate files and directories are removed.

Sudo privileges are required to run :code:`docker export`.

Optional :code:`ARGS` passed to :code:`mksquashfs` unchanged.

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

  .
  .
  .
  squashed /tmp/debian.sqfs OK
  $ ls -lh /tmp
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:37 debian.sqfs
