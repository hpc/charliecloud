Synopsis
========

::

  $ ch-builder2tar IMAGE OUTDIR

Description
===========

Flattens the Docker image tagged :code:`IMAGE` into a Charliecloud tarball in
directory :code:`OUTDIR`.

The Docker environment (e.g., :code:`ENV` statements) is placed in a file in
the tarball at :code:`$IMAGE/ch/environment`, in a form suitable for
:code:`ch-run --set-env`.

Sudo privileges are required to run :code:`docker export`.

Additional arguments:

  :code:`--nocompress`
    do not compress tarball

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ch-builder2tar hello /var/tmp
  57M /var/tmp/hello.tar.gz
  $ ls -lh /var/tmp
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz
