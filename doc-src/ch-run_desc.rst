Synopsis
========

::

   $ ch-run [OPTION...] NEWROOT CMD [ARG...]

Description
===========

Run command :code:`CMD` in a Charliecloud container using the flattened and unpacked image located in :code:`NEWROOT`.

    :code:`-b`, :code:`--bind=SRC[:DST]`
        mount :code:`SRC` at guest :code:`DST` (default :code:`/mnt/0`, :code:`/mnt/1`, etc.)

    :code:`-c`, :code:`--cd=DIR`
        initial working directory in container

    :code:`-g`, :code:`--gid=GID`
        run as :code:`GID` within container

    :code:`--is-setuid`
        exit successfully if compiled for setuid, else fail

    :code:`--no-home`
        do not bind-mount your home directory

    :code:`-t`, :code:`--private-tmp`
        use container-private :code:`/tmp`

    :code:`-u`, :code:`--uid=UID`
        run as :code:`UID` within container

    :code:`-v`, :code:`--verbose`
        be more verbose (debug if repeated)

    :code:`-w`, :code:`--write`
        mount image read-write

    :code:`-?`, :code:`--help`
        Give this help list

    :code:`--usage`
        Give a short usage message

    :code:`-V`, :code:`--version`
        print version and exit

Example
=======

Run the command :code:`echo hello` inside a Charliecloud container using the extracted image in :code:`/data/foo`::

    $ ch-run /data/foo -- echo hello
    hello
