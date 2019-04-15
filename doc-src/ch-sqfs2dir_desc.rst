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
# FIXME create example with real output
::

  $ ls -lh /var/tmp/images/hello/
  total 20K
  drwxr-xr-x.  2 jogas jogas 4.0K Jan 22 08:00 bin
  drwxr-xr-x.  2 jogas jogas    6 Oct 20 04:40 boot
  drwxr-xr-x.  2 jogas jogas    6 Apr 12 10:08 dev
  -rw-------.  1 jogas jogas   67 Apr 12 10:08 environment
  drwxr-xr-x. 31 jogas jogas 4.0K Apr 12 10:08 etc
  drwxr-xr-x.  2 jogas jogas   71 Apr 12 10:08 hello
  drwxr-xr-x.  2 jogas jogas    6 Oct 20 04:40 home
  drwxr-xr-x.  8 jogas jogas   96 Jan 22 08:00 lib
  drwxr-xr-x.  2 jogas jogas   34 Jan 22 08:00 lib64
  drwxr-xr-x.  2 jogas jogas    6 Jan 22 08:00 media
  drwxr-xr-x. 12 jogas jogas   96 Apr 12 10:16 mnt
  drwxr-xr-x.  2 jogas jogas    6 Jan 22 08:00 opt
  drwxr-xr-x.  2 jogas jogas    6 Oct 20 04:40 proc
  drwx------.  2 jogas jogas   37 Jan 22 08:00 root
  drwxr-xr-x.  3 jogas jogas   30 Jan 22 08:00 run
  drwxr-xr-x.  2 jogas jogas 4.0K Jan 22 08:00 sbin
  drwxr-xr-x.  2 jogas jogas    6 Jan 22 08:00 srv
  drwxr-xr-x.  2 jogas jogas    6 Oct 20 04:40 sys
  drwxrwxr-x.  2 jogas jogas    6 Apr 12 10:08 tmp
  drwxr-xr-x. 10 jogas jogas  105 Jan 22 08:00 usr
  drwxr-xr-x. 11 jogas jogas  139 Jan 22 08:00 var
  -rw-rw-r--.  1 jogas jogas   40 Apr 12 10:16 WEIRD_AL_YANKOVIC
  $ ch-dir2sqfs /var/tmp/images/hello /var/tmp/sqfs
  creating new squashfs image /var/tmp/sqfs/hello.sqfs
  /var/tmp/images/hello squashed ok
  $ ls -l /var/tmp/sqfs/
  hello.sqfs
