Synopsis
========

::

  $ ch-run [OPTION...] NEWROOT CMD [ARG...]

Description
===========

Run command :code:`CMD` in a Charliecloud container using the flattened and
unpacked image directory located at :code:`NEWROOT`.

  :code:`-b`, :code:`--bind=SRC[:DST]`
    mount :code:`SRC` at guest :code:`DST` (default :code:`/mnt/0`,
    :code:`/mnt/1`, etc.)

  :code:`-c`, :code:`--cd=DIR`
    initial working directory in container

  :code:`-g`, :code:`--gid=GID`
    run as group :code:`GID` within container

  :code:`--no-home`
    do not bind-mount your home directory (by default, your home directory is
    mounted at :code:`/home/$USER` in the container)

  :code:`-t`, :code:`--private-tmp`
    use container-private :code:`/tmp` (by default, :code:`/tmp` is shared with
    the host)

  :code:`-u`, :code:`--uid=UID`
    run as user :code:`UID` within container

  :code:`-v`, :code:`--verbose`
    be more verbose (debug if repeated)

  :code:`-w`, :code:`--write`
    mount image read-write (by default, the image is mounted read-only)

  :code:`-?`, :code:`--help`
    print help and exit

  :code:`--usage`
    print a short usage message and exit

  :code:`-V`, :code:`--version`
    print version and exit

Host files and directories available in container via bind mounts
=================================================================

In addition to any directories specified by the user with :code:`--bind`,
:code:`ch-run` has standard host files and directories that are bind-mounted
in as well.

The following host files and directories are bind-mounted at the same location
in the container. These cannot be disabled.

  * :code:`/dev`
  * :code:`/etc/passwd`
  * :code:`/etc/group`
  * :code:`/etc/hosts`
  * :code:`/etc/resolv.conf`
  * :code:`/proc`
  * :code:`/sys`

Three additional bind mounts can be disabled by the user:

  * Your home directory (i.e., :code:`$HOME`) is mounted at guest
    :code:`/home/$USER` by default. This is accomplished by mounting a new
    :code:`tmpfs` at :code:`/home`, which hides any image content under that
    path. If :code:`--no-home` is specified, neither of these things happens
    and the image's :code:`/home` is exposed unaltered.

  * :code:`/tmp` is shared with the host by default. If :code:`--private-tmp`
    is specified, a new :code:`tmpfs` is mounted on the guest's :code:`/tmp`
    instead.

  * If file :code:`/usr/bin/ch-ssh` is present in the image, it is
    over-mounted with the :code:`ch-ssh` binary in the same directory as
    :code:`ch-run`.

Example
=======

Run the command :code:`echo hello` inside a Charliecloud container using the
unpacked image at :code:`/data/foo`::

    $ ch-run /data/foo -- echo hello
    hello
