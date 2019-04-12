Synopsis
========

::

  $ ch-mountsqfs SQFS MOUNTDIR

Description
===========

Mounts Charliecloud squashfs :code:`SQFS` in target empty directory :code:`MOUNTDIR`
Creates :code:`MOUNTDIR` if it does not exist

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======
# TODO put real output in example section
::

  $ ls -lh /var/tmp/debian
  ls: cannot access '/var/tmp/debian': No such file or directory
  $ ch-mountsqfs ~/debian.sqfs /var/tmp/debian
  $ ls -lh /var/tmp/debian
  total 0
  drwxr-xr-x  2 shane shane  0 Jul 15  2018 bin
  drwxr-xr-x  2 shane shane  0 Jun 26  2018 boot
  drwxr-xr-x  2 shane shane  0 Apr  9 15:41 dev
  drwxr-xr-x 29 shane shane  0 Apr  9 15:41 etc
  drwxr-xr-x  2 shane shane  0 Jun 26  2018 home
  drwxr-xr-x  8 shane shane  0 Jul 15  2018 lib
  drwxr-xr-x  2 shane shane  0 Jul 15  2018 lib64
  drwxr-xr-x  2 shane shane  0 Jul 15  2018 media
  drwxr-xr-x 12 shane shane  0 Apr  9 15:41 mnt
  drwxr-xr-x  2 shane shane  0 Jul 15  2018 opt
  drwxr-xr-x  2 shane shane  0 Jun 26  2018 proc
  drwx------  2 shane shane  0 Jul 15  2018 root
  drwxr-xr-x  3 shane shane  0 Jul 15  2018 run
  drwxr-xr-x  2 shane shane  0 Jul 15  2018 sbin
  drwxr-xr-x  2 shane shane  0 Jul 15  2018 srv
  drwxr-xr-x  2 shane shane  0 Jun 26  2018 sys
  drwxrwxr-x  2 shane shane  0 Jul 15  2018 tmp
  drwxr-xr-x 10 shane shane  0 Jul 15  2018 usr
  drwxr-xr-x 11 shane shane  0 Jul 15  2018 var
  -rw-rw-r--  1 shane shane 50 Apr  9 15:41 WEIRD_AL_YANKOVIC

