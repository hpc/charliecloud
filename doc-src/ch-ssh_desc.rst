Synopsis
========

CH_RUN_ARGS="NEWROOT [ARG...]" :code:`ch-ssh` [OPTION...] HOST CMD [ARG...]

Description
===========

Runs command CMD in a container as specified in the CH_RUN_ARGS environment
variable on remote host HOST.

.. WARNING:: Words in CH_RUN_ARGS are delimited by spaces only; it is not shell syntax

Example
=======

Run the command :code:`echo hello` inside a Charliecloud container using the extracted image in :code:`/data/foo`
on host example.com::

    $ export CH_RUN_ARGS=/data/foo
    $ ch-ssh example.com -- echo hello
    hello
