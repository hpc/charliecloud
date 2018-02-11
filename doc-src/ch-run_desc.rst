Synopsis
========

:code:`ch-run` [OPTION...] NEWROOT CMD [ARG...]

Description
===========

Run command CMD in a Charliecloud container using the flattened and unpacked image located in NEWROOT.

    :code:`-b, --bind=`\SRC[:DST]
        mount SRC at guest DST (default /mnt/0, /mnt/1, etc.)

    :code:`-c, --cd=`\DIR
        initial working directory in container

    :code:`-g, --gid=`\GID
        run as GID within container

    :code:`--is-setuid`
        exit successfully if compiled for setuid, else fail

    :code:`--no-home`
        do not bind-mount your home directory

    :code:`-t, --private-tmp`
        use container-private /tmp

    :code:`-u, --uid=`\UID
        run as UID within container

    :code:`-v, --verbose`
        be more verbose (debug if repeated)

    :code:`-w, --write`
        mount image read-write

    :code:`-?, --help`
        Give this help list

    :code:`--usage`
        Give a short usage message

    :code:`-V, --version`
        print version and exit

Example
=======

Run the command :code:`echo hello` inside a Charliecloud container using the extracted image in :code:`/data/foo`::

    $ ch-run /data/foo -- echo hello
    hello
