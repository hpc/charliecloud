Synopsis
========

::

   $ ch-build [ARGS ...]

Description
===========

Build a Docker image as specified by file :code:`Dockerfile` using
:code:`docker build`. It requires sudo privileges to run the docker command.
If no location is provided for the :code:`Dockerfile` (using the
:code:`--file` argument of :code:`docker build`), the current working
directory is assumed. :code:`ch-build` respects your HTTP proxy settings
(details are explained below). ARGS different from those listed below are
passed unchanged to :code:`docker build`.

    :code:`--help`
        Give this help list

    :code:`--version`
        print version and exit

Example
=======

Create a Docker image according to the specifications in the file
:code:`Dockerfile` located in the directory :code:`/foo`::

    $ ch-build --file=/foo/Dockerfile
