Synopsis
========

::

  $ ch-docker2sqfs IMAGE OUTDIR

Description
===========

Flattens the Docker image tagged :code:`IMAGE` into a Charliecloud squashfs in
directory :code:`OUTDIR`.

Executes :code:`ch-docker2tar`, then :code:`ch-tar2sqfs`

Intermediate files and directories are removed.

Sudo privileges are required to run :code:`docker export`.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======
# FIXME create example with real output
::

  $ ch-docker2sqfs hello /var/tmp
  creating new squashfs image /var/tmp/hello.sqfs
  squashed ok
  $ ls -lh /var/tmp
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.sqfs
