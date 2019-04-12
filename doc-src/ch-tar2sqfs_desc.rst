Synopsis
========

::

  $ ch-tar2sqfs TARBALL OUTDIR

Description
===========

Create Charliecloud squashfs with name matching :code:`TARBALL` under directory :code:`OUTDIR`

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
# TODO create example with real output when ready
::

  $ ls -lh /var/tmp
  total 57M
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz
  $ ch-tar2dir /var/tmp/hello.tar.gz /var/tmp
  creating new image /var/tmp/hello
  /var/tmp/hello unpacked ok
  $ ls -lh /var/tmp
  total 57M
  drwxr-x--- 22 reidpr reidpr 4.0K Feb 13 16:29 hello
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz
