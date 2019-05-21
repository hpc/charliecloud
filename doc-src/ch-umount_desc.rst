Synopsis
========

::

  $ ch-umount MOUNTDIR

Description
===========

Unmounts Charliecloud SquashFS file at target directory :code:`MOUNTDIR`.
Removes empty :code:`MOUNTDIR` after successful unmounting.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ls /tmp/debian
  bin   dev          etc   lib    media  opt   root  sbin  sys  usr  WEIRD_AL_YANKOVIC
  boot  environment  home  lib64  mnt    proc  run   srv   tmp  var
  $ ch-umount /tmp/debian
  unmounted and removed /tmp/debian
  $ ls -lh /tmp/debian
  ls: cannot access /tmp/debian: No such file or directory