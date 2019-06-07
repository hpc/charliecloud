Synopsis
========

::

  $ ch-mount SQFS PARENTDIR

Description
===========

Create new empty directory named :code:`SQFS` with suffix (e.g.,
:code:`.sqfs`) removed, then mount :code:`SQFS` on this new directory. This
new directory must not already exist.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ls -lh /var/tmp
  total 41M
  -rw-r--r-- 1 charlie charlie 41M Apr 23 14:41 debian.sqfs
  $ ch-mount /var/tmp/debian.sqfs /var/tmp
  $ ls /var/tmp/debian
  bin   dev          etc   lib    media  opt   root  sbin  sys  usr  WEIRD_AL_YANKOVIC
  boot  environment  home  lib64  mnt    proc  run   srv   tmp  var
