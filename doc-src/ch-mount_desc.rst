Synopsis
========

::

  $ ch-mount SQFS PARENTDIR

Description
===========

Creates new empty directory with name corresponding to :code:`SQFS` under :code:`PARENTDIR` with suffix :code:`.sqfs` removed,
then mounts :code:`SQFS` in this new directory. 

If this new directory exists, the program will exit with an error.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======
# FIXME create example with real output
::

  $ ls -lh /tmp
  total 41M
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:41 debian.sqfs
  $ ch-mount /tmp/debian.sqfs /tmp
  $ ls -lh /tmp/debian
  total 0
  drwxr-xr-x  2 charlie charlie  0 Mar 26 06:00 bin
  drwxr-xr-x  2 charlie charlie  0 Feb  3 06:01 boot
  drwxr-xr-x  2 charlie charlie  0 Apr 23 14:39 dev
  -rw-------  1 charlie charlie 67 Apr 23 14:39 environment
  drwxr-xr-x 29 charlie charlie  0 Apr 23 14:39 etc
  drwxr-xr-x  2 charlie charlie  0 Feb  3 06:01 home
  drwxr-xr-x  8 charlie charlie  0 Mar 26 06:00 lib
  drwxr-xr-x  2 charlie charlie  0 Mar 26 06:00 lib64
  drwxr-xr-x  2 charlie charlie  0 Mar 26 06:00 media
  drwxr-xr-x 12 charlie charlie  0 Apr 23 14:40 mnt
  drwxr-xr-x  2 charlie charlie  0 Mar 26 06:00 opt
  drwxr-xr-x  2 charlie charlie  0 Feb  3 06:01 proc
  drwx------  2 charlie charlie  0 Mar 26 06:00 root
  drwxr-xr-x  3 charlie charlie  0 Mar 26 06:00 run
  drwxr-xr-x  2 charlie charlie  0 Mar 26 06:00 sbin
  drwxr-xr-x  2 charlie charlie  0 Mar 26 06:00 srv
  drwxr-xr-x  2 charlie charlie  0 Feb  3 06:01 sys
  drwxrwxr-x  2 charlie charlie  0 Mar 26 06:00 tmp
  drwxr-xr-x 10 charlie charlie  0 Mar 26 06:00 usr
  drwxr-xr-x 11 charlie charlie  0 Mar 26 06:00 var
  -rw-rw-r--  1 charlie charlie 40 Apr 23 14:40 WEIRD_AL_YANKOVIC