Synopsis
========

::

  $ ch-dir2squash IMGDIR OUTDIR [ARGS ...]

Description
===========

Create Charliecloud SquashFS file from image directory :code:`IMGDIR` under
directory :code:`OUTDIR`, named as last component of :code:`IMGDIR` plus
suffix :code:`.sqfs`.

Optional :code:`ARGS` will passed to :code:`mksquashfs` unchanged.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ch-dir2squash /var/tmp/debian /var/tmp
  Parallel mksquashfs: Using 6 processors
  Creating 4.0 filesystem on /var/tmp/debian.sqfs, block size 131072.
  [...]
  -rw-r--r--  1 charlie charlie 41M Apr 23 14:41 /var/tmp/debian.sqfs
