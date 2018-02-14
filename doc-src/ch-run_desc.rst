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

  :code:`--is-setuid`
    exit successfully if compiled for setuid, else fail

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

Example
=======

Run the command :code:`echo hello` inside a Charliecloud container using the
unpacked image at :code:`/data/foo`::

    $ ch-run /data/foo -- echo hello
    hello
