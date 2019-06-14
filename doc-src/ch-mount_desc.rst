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

  $ ch-mount /var/tmp/debian.sqfs /var/tmp
  $ ls /var/tmp/debian
  bin   dev  home  lib64  mnt  proc  run   srv  tmp  var
  boot  etc  lib   media  opt  root  sbin  sys  usr  WEIRD_AL_YANKOVIC
