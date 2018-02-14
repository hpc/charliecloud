Synopsis
========

::

  $ ch-build2dir CONTEXT DEST [ARGS ...]

Description
===========

Build a Docker image as specified by the file :code:`Dockerfile` in the
current working directory and context directory :code:`CONTEXT`. Unpack it in
:code:`DEST`.

Sudo privileges are required to run the :code:`docker` command.

This runs the following command sequence: :code:`ch-build`,
:code:`ch-docker2tar`, and :code:`ch-tar2dir` but provides less flexibility
than the individual commands.

Arguments:

  :code:`CONTEXT`
    Docker context directory

  :code:`DEST`
    directory in which to place image tarball and directory

  :code:`ARGS`
    additional arguments passed to :code:`ch-build`

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit
