Synopsis
========

:code:`ch-docker-run` [-i] [-b HOSTDIR:GUESTDIR ...] TAG CMD [ARGS ...]

Description
===========

Runs the command CMD in a docker container as specified by TAG. This requires sudo privileges.
The command CMD is run under your user ID. The users and groups inside the container match those on the host.

.. note::

   This command is intended as a convenience for debugging images and
   Charliecloud. Routine use for running applications is not recommended.
   Instead, use :code:`ch-run`.

..

    :code:`--help`
        Give this help list

    :code:`--version`
        print version and exit

    :code:`-i`
        Run interactively with a pseudo-TTY

    :code:`-b`
        Bind-mount HOSTDIR at GUESTDIR inside the container (can be repeated)
