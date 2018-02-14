Synopsis
========

::

  $ ch-docker-run [-i] [-b HOSTDIR:GUESTDIR ...] TAG CMD [ARGS ...]

Description
===========

Runs the command :code:`CMD` in a Docker container using the image named
:code:`TAG`.

Sudo privileges are required for :code:`docker run`.

:code:`CMD` is run under your user ID. The users and groups inside the
container match those on the host.

.. note::

   This command is intended as a convenience for debugging images and
   Charliecloud. Routine use for running applications is not recommended.
   Instead, use :code:`ch-run`.

Arguments:

  :code:`-i`
    run interactively with a pseudo-TTY

  :code:`-b`
    bind-mount :code:`HOSTDIR` at :code:`GUESTDIR` inside the container (can
    be repeated)

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

