Synopsis
========

::

  $ ch-tar2squash TARBALL OUTDIR [ARGS ...]

Description
===========

Create Charliecloud squashfs from :code:`TARBALL`  in directory :code:`OUTDIR`

The resulting squashfs has a name corresponding to :code:`TARBALL` with a :code:`.sqfs` suffix

Executes :code:`ch-tar2dir` and :code:`ch-dir2sqfs`

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
  total 43M
  -rw-rw-r-- 1 charlie charlie 43M Apr 23 14:49 debian.tar.gz
  $ ch-tar2squash /tmp/debian.tar.gz /tmp
  [=============================================================\] 5325/5325 100%
  squashed /tmp/debian.sqfs OK
  $ ls -lh /tmp
  total 83M
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:50 debian.sqfs
  -rw-rw-r-- 1 charlie charlie 43M Apr 23 14:49 debian.tar.gz