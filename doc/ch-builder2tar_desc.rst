Synopsis
========

::

  $ ch-builder2tar [-a ARCH] [-b BUILDER] [--nocompress] IMAGE OUTDIR

Description
===========

Flatten the builder image tagged :code:`IMAGE` into a Charliecloud tarball in
directory :code:`OUTDIR`.

The builder-specified environment (e.g., :code:`ENV` statements) is placed in
a file in the tarball at :code:`$IMAGE/ch/environment`, in a form suitable for
:code:`ch-run --set-env`.

If multiple images of same tag :code:`IMAGE` exist in storage with different
archictectures, prefer the one that most closely resembles the host. If the
host's architecture doesn't match any image in storage then use the following
defaults in order of precedence: 1) image tagged :code:`IMAGE` with architecure
:code:`arch-unspecified`; 2) first image matching image tagged :code:`IMAGE`
(architectures are searched in alphabetical order).

See :code:`ch-build(1)` for details on specifying the builder.

Additional arguments:
  :code:`-a`, :code:`--arch ARCH[/VARIANT]`
    Use specified architecture `ARCH[/VARIANT]` for image tagged :code:`IMAGE.`

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

Hello world image.

::
  $ ch-builder2tar hello /var/tmp
  57M /var/tmp/hello.tar.gz
  $ ls -lh /var/tmp
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz

Hello world with architecture matching host.

::
  FIXME: use real output

  $ uname -m
  x86_64
  $ ch-builder2tar hello /var/tmp
  image architecture: amd64
  57M /var/tmp/hello.tar.gz
  $ ls -lh /var/tmp
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz

Hello world with multiple architectures, none matching the host; unspecifed
default.

::
  FIXME: use real output

  $ uname -m
  randoarch99
  $ ch-builder2tar hello /var/tmp
  image architecture: unspecified
  57M /var/tmp/hello.tar.gz
  $ ls -lh /var/tmp
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz

Hellow world with multiple architectures, none matching the host, no
unspecified architecture variant.

::
  FIXME: use real output

  $ uname -m
  randoarch99
  $ ch-builder2tar hello /var/tmp
  image architecture: amd64
  57M /var/tmp/hello.tar.gz
  $ ls -lh /var/tmp
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz
