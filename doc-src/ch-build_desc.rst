Synopsis
========

::

  $ ch-build -t TAG [ARGS ...] CONTEXT

Description
===========

Build a Docker image named :code:`TAG` described by Dockerfile
:code:`./Dockerfile` or as specified. Pass the HTTP proxy environment
variables through with :code:`--build-arg`.

Sudo privileges are required to run the :code:`docker` command.

Arguments:

  :code:`--file`
    Dockerfile to use (default: :code:`./Dockerfile`)

  :code:`-t`
    name (tag) of Docker image to build

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Additional arguments are accepted and passed unchanged to :code:`docker
build`.

Examples
========

Create a Docker image tagged :code:`foo` and specified by the file
:code:`Dockerfile` located in the current working directory. Use :code:`/bar`
as the Docker context directory::

  $ ch-build -t foo /bar

Equivalent to above::

  $ ch-build -t foo --file=./Dockerfile /bar

Instead, use the Dockerfile :code:`/baz/qux.docker`::

  $ ch-build -t foo --file=/baz/qux.docker /bar

Note that calling your Dockerfile anything other than :code:`Dockerfile` will
confuse people.
