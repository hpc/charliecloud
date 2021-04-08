Synopsis
========

::

  $ ch-builder2tar [-b BUILDER] [--nocompress] IMAGE OUTDIR

Description
===========

Flatten the builder image tagged :code:`IMAGE` into a Charliecloud tarball in
directory :code:`OUTDIR`.

The builder-specified environment (e.g., :code:`ENV` statements) is placed in
a file in the tarball at :code:`$IMAGE/ch/environment`, in a form suitable for
:code:`ch-run --set-env`.

See :code:`ch-build(1)` for details on specifying the builder.

Additional arguments:

  :code:`-b`, :code:`--builder BUILDER`
    Use specified builder; if not given, use :code:`$CH_BUILDER` or default.

  :code:`--nocompress`
    Do not compress tarball.

  :code:`--help`
    Print help and exit.

  :code:`--version`
    Print version and exit.

Example
=======

::

  $ ch-builder2tar hello /var/tmp
  57M /var/tmp/hello.tar.gz
  $ ls -lh /var/tmp
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz
