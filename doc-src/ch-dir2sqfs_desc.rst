Synopsis
========

::

  $ ch-dir2sqfs IMGDIR OUTDIR

Description
===========

Create Charliecloud squashfs from image directory :code:`IMGDIR` under directory :code:`OUTDIR`
with the same name as :code:`IMGDIR`, with suffix :code:`.sqfs`

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--verbose`
    be more verbose

  :code:`--version`
    print version and exit


Example
=======
# FIXME create example with real output
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
  ch-dir2sqfs /var/tmp/hello /var/tmp
  creating new squashfs image /var/tmp/sqfs/hello.sqfs
  squashed /var/tmp/hello ok
  ls -lh /var/tmp
  drwxr-x--- 22 reidpr reidpr 4.0K Feb 13 16:29 hello
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz
  -rw-r--r-- 16 reidpr reidpr  57M Feb 13 17:12 hello.sqfs