Synopsis
========

::

  $ ch-build2dir -t TAG [ARGS ...] CONTEXT OUTDIR

Description
===========

Build a Docker image named :code:`TAG` described by a Dockerfile (default
:code:`$CONTEXT/Dockerfile`) and unpack it into :code:`OUTDIR/TAG`. This is a
wrapper for :code:`ch-build`, :code:`ch-builder2tar`, and :code:`ch-tar2dir`;
see also those man pages.

Arguments:

  :code:`ARGS`
    additional arguments passed to :code:`ch-build`

  :code:`CONTEXT`
    Docker context directory

  :code:`OUTDIR`
    directory in which to place image directory (named :code:`TAG`) and
    temporary tarball

  :code:`-t TAG`
    name (tag) of Docker image to build

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Examples
========

To build using :code:`./Dockerfile` and create image directory
:code:`/var/tmp/foo`::

  $ ch-build2dir -t foo . /var/tmp

Same as above, but build with a different Dockerfile::

  $ ch-build2dir -t foo -f ./Dockerfile.foo . /var/tmp
