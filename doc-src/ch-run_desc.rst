Synopsis
========

``ch-run`` [OPTION...] NEWROOT CMD [ARG...]    

Description
===========

Run command CMD in a Charliecloud container using the flattened and unpacked image located in NEWROOT.

    ``-b, --bind=``\SRC[:DST]
        mount SRC at guest DST (default /mnt/0, /mnt/1, etc.)

    ``-c, --cd=``\DIR
        initial working directory in container

    ``-g, --gid=``\GID
        run as GID within container

    ``--is-setuid``
        exit successfully if compiled for setuid, else fail

    ``--no-home``
        do not bind-mount your home directory

    ``-t, --private-tmp``
        use container-private /tmp

    ``-u, --uid=``\UID
        run as UID within container

    ``-v, --verbose``
        be more verbose (debug if repeated)

    ``-w, --write``
        mount image read-write

    ``-?, --help``
        Give this help list

    ``--usage``
        Give a short usage message

    ``-V, --version``
        print version and exit

Example
=======

Run the command ``echo hello`` inside a Charliecloud container using the extracted image in ``/data/foo``::

    $ ch-run /data/foo -- echo hello
    hello
