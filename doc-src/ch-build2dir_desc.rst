Synopsis
========

:code:`ch-build2dir` CONTEXT DEST [ARGS ...]

Description
===========

Build a Docker image as specified by the file :code:`Dockerfile` in the current working
directory and unpack it. This runs the following command sequence: :code:`ch-build`,
:code:`ch-docker2tar` and :code:`ch-tar2dir` but provides less flexibility than the
individual commands. Running this command requires sudo privileges.
The meaning of provided arguments is as follows:

    CONTEXT
        Docker context directory

    DEST
        Directory in which to place image tarball and directory

    ARGS
        Additional arguments passed to :code:`ch-build`

    :code:`--help`
        Give this help list

    :code:`--version`
        print version and exit

.. include:: ./docker_tips.rst
