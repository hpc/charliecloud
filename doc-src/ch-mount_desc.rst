Synopsis
========

::

  $ ch-mount SQFS PARENTDIR

Description
===========

Creates new empty directory with name corresponding to :code:`SQFS`
under :code:`PARENTDIR` with suffix :code:`.sqfs` removed,
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
  $ ls /tmp/debian
  bin   dev          etc   lib    media  opt   root  sbin  sys  usr  WEIRD_AL_YANKOVIC
  boot  environment  home  lib64  mnt    proc  run   srv   tmp  var