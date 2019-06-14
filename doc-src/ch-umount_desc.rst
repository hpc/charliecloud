Synopsis
========

::

  $ ch-umount MOUNTDIR

Description
===========

Unmount Charliecloud SquashFS file at target directory :code:`MOUNTDIR`.
Remove empty :code:`MOUNTDIR` after successful unmounting.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Example
=======

::

  $ ls /var/tmp/debian
  bin   dev  home  lib64  mnt  proc  run   srv  tmp  var
  boot  etc  lib   media  opt  root  sbin  sys  usr  WEIRD_AL_YANKOVIC
  $ ch-umount /var/tmp/debian
  unmounted and removed /var/tmp/debian
  $ ls /var/tmp/debian
  ls: cannot access /var/tmp/debian: No such file or directory
