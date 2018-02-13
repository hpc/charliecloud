Synopsis
========

::

  $ CH_RUN_ARGS="NEWROOT [ARG...]"
  $ ch-ssh [OPTION...] HOST CMD [ARG...]

Description
===========

Runs command :code:`CMD` in a Charliecloud container on remote host
:code:`HOST`. Use the content of environment variable :code:`CH_RUN_ARGS` as
the arguments to :code:`ch-run` on the remote host.

.. note::

   Words in :code:`CH_RUN_ARGS` are delimited by spaces only; it is not shell
   syntax.

Example
=======

On host bar.example.com, run the command :code:`echo hello` inside a
Charliecloud container using the unpacked image at :code:`/data/foo` with
starting directory :code:`/baz`::

  $ hostname
  foo
  $ export CH_RUN_ARGS='--cd /baz /data/foo'
  $ ch-ssh bar.example.com -- hostname
  bar
