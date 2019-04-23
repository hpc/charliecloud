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

  :code:`--verbose`
    be more verbose

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
  $ ch-docker2squash debian /tmp
  [=============================================================|] 5325/5325 100%
  squashed /tmp/debian.sqfs OK
  $ ls -lh /tmp
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:37 debian.sqfs