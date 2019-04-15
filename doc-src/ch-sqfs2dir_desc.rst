Synopsis
========

::

  $ ch-sqfs2dir SQFS OUTDIR

Description
===========

Extract the squashfs :code:`SQFS` into a subdirectory of :code:`OUTDIR`.
:code:`SQFS` must contain a sqaushfs filesystem, e.g., as created by
:code:`ch-docker2sqfs`, and end with a :code:`.sqfs` suffix.

Inside :code:`OUTDIR`, an image directory will be created whose name corresponds to 
the name of the :code:`SQFS` with the :code:`.sqfs` suffix removed. If such
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
# FIXME create example with real output
::

  $ ls -lh /var/tmp/
  total 55M
  -rw-rw-r-- 1 rgoff rgoff 55M Apr 15 14:30 debian9.sqfs
  $ ch-sqfs2dir /var/tmp/debian9.sqfs /var/tmp/
  unsquashing /var/tmp/debian0.sqfs
  unsquashed ok
  $ ls -lh /var/tmp/
  -rw-rw-r-- 1 rgoff rgoff 55M Apr 15 14:30 debian9.sqfs
  drw-rw-r-- 1 rgoff rgoff 55M Apr 15 14:30 debian9