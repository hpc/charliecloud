Synopsis
========

::

  $ ch-dir2sqfs DIR OUTDIR

Description
===========

Create Charliecloud squashfs from directory :code:`DIR` under directory :code:`OUTDIR`
with the same name as :code:`DIR`, with suffix :code:`.sqfs`

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--verbose`
    be more verbose

  :code:`--version`
    print version and exit


Example
=======
# TODO add example output when complete
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