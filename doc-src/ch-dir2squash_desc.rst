Synopsis
========

::

  $ ch-dir2squash IMGDIR OUTDIR [ARGS ...]

Description
===========

Create Charliecloud SquashFS file from image directory :code:`IMGDIR` under 
directory :code:`OUTDIR` with the same name as :code:`IMGDIR`,
with suffix :code:`.sqfs`

Optional :code:`ARGS` will be passed to :code:`mksquashfs`

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ls -lh /tmp/
  total 0
  drwxrwxr-x 21 charlie charlie 286 Apr 23 14:40 debian
  $ ch-dir2squash /tmp/debian /tmp
  Parallel mksquashfs: Using 6 processors
  Creating 4.0 filesystem on /tmp/debian.sqfs, block size 131072.
  [=========================================================================/] 5323/5323 100%

  .
  .
  .
  squashed /tmp/debian.sqfs OK
  $ ls -lh /tmp
  total 41M
  drwxrwxr-x 21 charlie charlie 286 Apr 23 14:40 debian
  -rw-r--r--  1 charlie charlie 41M Apr 23 14:41 debian.sqfs