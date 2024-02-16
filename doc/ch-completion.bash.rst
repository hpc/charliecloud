.. _ch-completion.bash:

:code:`ch-completion.bash`
++++++++++++++++++++++++++

.. only:: not man

   Tab completion for the Charliecloud command line.


Synopsis
========

::

    $ source ch-completion.bash


Description
===========

:code:`ch-completion.bash` provides tab completion for the charliecloud
command line. Currently, tab completion is available for Bash users for the
executables :code:`ch-image`, :code:`ch-run`, and :code:`ch-convert`.

We do not currently install the file if Charliecloud is built from source (see
`issue #1842 <https://github.com/hpc/charliecloud/issues/1842>`_). In this
case, source it from the Charliecloud source code::

    $ source $CHARLIECLOUD_SOURCE_PATH/bin/ch-completion.bash

If you installed with a distribution package, the procedure is probably nicer.
See your distro’s docs if you installed a package.)

Disable completion with the utility function :code:`ch-completion` added to
your environment when the above is sourced::

    $ ch-completion --disable


Dependencies
============

Tab completion has these additional dependencies:

* Bash ≥ 4.3.0

* :code:`bash-completion` library (`GitHub
  <https://github.com/scop/bash-completion>`_, or it probably comes with your
  distribution, `e.g.
  <https://packages.debian.org/bullseye/bash-completion>`_)


.. _ch-completion_func:

:code:`ch-completion`
=====================

Utility function for :code:`ch-completion.bash`.

Synopsis
--------

::

    $ ch-completion [ OPTIONS ]


Description
-----------

:code:`ch-completion` is a function to manage Charliecloud’s tab completion.
It is added to the environment when completion is sourced. The option(s) given
specify what to do:

:code:`--disable`
    Disable tab completion for all Charliecloud executables.

:code:`--help`
    Print help message.

:code:`--version`
    Print version of tab completion that’s currently enabled.

:code:`--version-ok`
    Verify that tab completion version is consistent with that of
    :code:`ch-image`.


Debugging
=========

Tab completion can write debugging logs to :code:`/tmp/ch-completion.log`.
Enable this by setting the environment variable :code:`CH_COMPLETION_DEBUG`.
(This is primarily intended for developers.)


..  LocalWords:  func
