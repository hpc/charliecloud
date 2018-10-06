Synopsis
========

::

  $ ch-dir2tar DIR TARBALL

Description
===========

Pack the Linux filesystem image directory :code:`DIR` (as created by :code:`ch-docker2tar`
followed by :code:`ch-tar2dir`) into a Charliecloud tarball :code:`TARBALL`.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--verbose`
    be more verbose

Example
=======

::

  $ ls -lh /var/tmp/alpine
  total 4.1M
  -rw-r--r--.  1 charlie 4.1M Oct  6 11:35 alpine.tar.gz
  drwxr-xr-x.  2 charlie 4.0K Sep 11 16:23 bin/
  drwxr-xr-x.  2 charlie    6 Oct  5 20:09 dev/
  drwxr-xr-x. 15 charlie 4.0K Oct  5 20:09 etc/
  drwxr-xr-x.  2 charlie    6 Sep 11 16:23 home/
  drwxr-xr-x.  5 charlie  278 Sep 11 16:23 lib/
  drwxr-xr-x.  5 charlie   44 Sep 11 16:23 media/
  drwxr-xr-x. 12 charlie   96 Oct  5 20:09 mnt/
  drwxr-xr-x.  2 charlie    6 Sep 11 16:23 proc/
  drwx------.  2 charlie    6 Sep 11 16:23 root/
  drwxr-xr-x.  2 charlie    6 Sep 11 16:23 run/
  drwxr-xr-x.  2 charlie 4.0K Sep 11 16:23 sbin/
  drwxr-xr-x.  2 charlie    6 Sep 11 16:23 srv/
  drwxr-xr-x.  2 charlie    6 Sep 11 16:23 sys/
  drwxr-xr-x.  2 charlie    6 Sep 11 16:23 tmp/
  drwxr-xr-x.  7 charlie   66 Sep 11 16:23 usr/
  drwxr-xr-x. 11 charlie  125 Sep 11 16:23 var/
  -rw-r--r--.  1 charlie   50 Oct  5 20:09 WEIRD_AL_YANKOVIC
  $ ch-dir2tar /var/tmp/alpine /var/tmp/tarballs/alpine.tar.gz
  /var/tmp/tarballs/alpine.tar.gz packed ok
  $ ls -lh /var/tmp/tarballs/
  total 6.2M
  -rw-r--r--. 1 charlie 6.2M Oct  6 12:23 alpine.tar.gz
