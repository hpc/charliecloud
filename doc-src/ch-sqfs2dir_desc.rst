Synopsis
========

::

  $ ch-sqfs2dir SQFS OUTDIR

Description
===========

Extract the squashfs :code:`SQFS` into a subdirectory of :code:`OUTDIR`
matching the name of :code:`SQFS` with the suffix :code:`.sqfs` removed.

# TODO Talk about this
:code:`SQFS` must contain a Linux filesystem image, e.g. as created by
:code:`ch-docker2sqfs`

#TODO Talk about this
Inside :code:`DIR`, a subdirectory will be created whose name corresponds to
the name of the squashfs with :code:`.sqfs` removed. If such
a directory exists already and appears to be a Charliecloud container image,
it is removed and replaced. If the existing directory doesn't appear to be a
container image, the script aborts with an error.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--verbose`
    be more verbose

  :code:`--version`
    print version and exit

.. warning::

   Placing :code:`DIR` on a shared file system can cause significant metadata
   load on the file system servers. This can result in poor performance for
   you and all your colleagues who use the same file system. Please consult
   your site admin for a suitable location.

Example
=======
# TODO create example with real output
::

  $ ls -lh /var/tmp
  total 57M
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.sqfs
  $ ch-tar2dir /var/tmp/hello.tar.gz /var/tmp
  creating new image /var/tmp/hello
  /var/tmp/hello unpacked ok
  $ ls -lh /var/tmp
  total 57M
  drwxr-x--- 22 reidpr reidpr 4.0K Feb 13 16:29 hello
  -rw-r-----  1 reidpr reidpr  57M Feb 13 16:14 hello.tar.gz
