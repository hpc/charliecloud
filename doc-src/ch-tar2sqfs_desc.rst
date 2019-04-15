Synopsis
========

::

  $ ch-tar2sqfs TARBALL OUTDIR

Description
===========

Create Charliecloud squashfs from :code:`TARBALL`  in directory :code:`OUTDIR`

The resulting squashfs has a name corresponding to :code:`TARBALL` with a :code:`.sqfs` suffix

Executes :code:`ch-tar2dir` and :code:`ch-dir2sqfs`

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

.. warning::
   # TODO ask if this warning applies
   Placing :code:`OUTDIR` on a shared file system can cause significant metadata
   load on the file system servers. This can result in poor performance for
   you and all your colleagues who use the same file system. Please consult
   your site admin for a suitable location.

Example
=======
# FIXME create example with real output
::

  $ ls -lh /var/tmp
  total 57M
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz
  $ ch-docker2tar debian9 .
  rgoff 15
  $ ls -lh
  total 55M
  -rw-rw-r-- 1 rgoff rgoff 55M Apr 15 14:30 debian9.tar.gz
  $ ch-tar2sqfs debian9.tar.gz .
  creating new squashfs image /var/tmp/sqfs/hello.sqfs
  squashed ok
  $ ls -lh
  total 110M
  -rw-rw-r-- 1 rgoff rgoff 55M Apr 15 14:30 debian9.tar.gz
  -rw-rw-r-- 1 rgoff rgoff 55M Apr 15 14:30 debian9.sqfs
