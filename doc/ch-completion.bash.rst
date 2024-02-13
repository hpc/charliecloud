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

:code:`ch-completion.bash` implements tab completion for the charliecloud
command line. This feature is experimental, but should be stable enough for
general use. Currently, tab completion is only available for Bash users, though
support for other shells (e.g. zsh and tcsh) is a planned feature. Tab
completion has been implemented for the following executables:

* :code:`ch-image`
* :code:`ch-run`
* :code:`ch-convert`

Tab completion can be enabled by sourcing :code:`ch-completion.bash` with the
Charliecloud :code:`bin` directory in your :code:`PATH`:

::

    $ source ch-completion.bash

Tab completion can be disabled by specifying the :code:`--disable` option of the
:code:`ch-completion` function (see :ref:`ch-completion_func`):

::

    $ ch-completion --disable


Dependencies
============

As noted above, tab completion is currently only available for Bash users. The
feature has the following additional dependencies:

* Bash ≥ 4.3.0
* :code:`bash-completion`



.. _ch-completion_func:

:code:`ch-completion`
=====================

Utility funciton for :code:`ch-completion.bash`.


Synopsis
--------


::

    $ ch-completion [ OPTIONS ]


Description
-----------

:code:`ch-completion` is a function available to users that provides various
utilities related to tab completion.

:code:`--disable`
    Disable tab completion for all executables.

:code:`--help`
    Print help message.

:code:`--version`
    Print version of tab completion that's currently enabled.

:code:`--version-ok`
    Verify that tab completion version is consistent with that of
    :code:`ch-image`.


Debugging
=========

:code:`ch-completion.bash` can optionally write debugging info to the log file
:code:`/tmp/ch-completion.log`. This feature can be enabled by setting the
environment variable :code:`CH_COMPLETION_DEBUG`. Note that this is primarily
intended for developers.