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

  $ docker image list | fgrep debian
  REPOSITORY   TAG       IMAGE ID       CREATED      SIZE
  debian       stretch   2d337f242f07   3 weeks ago  101MB
  $ ch-docker2squash debian /var/tmp
  Parallel mksquashfs: Using 6 processors
  Creating 4.0 filesystem on /var/tmp/debian.sqfs, block size 131072.
  [...]
  squashed /var/tmp/debian.sqfs OK
  $ ls -lh /var/tmp/debian*
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:37 debian.sqfs
