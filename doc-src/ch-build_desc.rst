Synopsis
========

``ch-build`` [ARGS ...]

Description
===========

Build a Docker image as specified by file ``Dockerfile`` using ``docker build``.
It requires sudo privileges to run the docker command. If no location is provided for the
``Dockerfile`` (using the ``--file`` argument of ``docker build``), the current working directory
is assumed. ``ch-build`` respects your HTTP proxy settings (details are explained below).
ARGS different from those listed below are passed unchanged to ``docker build``.

    ``--help``
        Give this help list

    ``--version``
        print version and exit

Example
=======

Create a Docker image according to the specifications in the file ``Dockerfile`` located in
the directory ``/foo``::

    $ ch-build --file=/foo/Dockerfile

.. include:: ./docker_tips.rst
