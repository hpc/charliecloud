Synopsis
========

::

  $ ch-tar2dir TARBALL DIR

Description
===========

Extract the tarball :code:`TARBALL` into a subdirectory of :code:`DIR`.
:code:`TARBALL` must contain a Linux filesystem image, e.g. as created by
:code:`ch-builder2tar`, and be compressed with :code:`gzip` or :code:`xz`. If
:code:`TARBALL` has no extension, try appending :code:`.tar.gz` and
:code:`.tar.xz`.

Inside :code:`DIR`, a subdirectory will be created whose name corresponds to
the name of the tarball with :code:`.tar.gz` or other suffix removed. If such
a directory exists already and appears to be a Charliecloud container image,
it is removed and replaced. If the existing directory doesn't appear to be a
container image, the script aborts with an error.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

.. warning::

   Placing :code:`DIR` on a shared file system can cause significant metadata
   load on the file system servers. This can result in poor performance for
   you and all your colleagues who use the same file system. Please consult
   your site admin for a suitable location.

Example
=======

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
