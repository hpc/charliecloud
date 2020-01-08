Synopsis
========

::

   $ ch-grow IMAGE[:TAG][@DIGEST] [OPTIONS]

Description
===========

.. warning::

   This script is experimental. Please report the bugs you find so we can fix
   them!

Pull an image named :code:`IMAGE` by reference :code:`TAG` or :code:`DIGEST`
(latter prioritized) from the open docker registry; unpack the image for
manipulation by :code:`ch-grow`.

Other arguments:

  :code:`-i`, :code:`--inspect`
    Dump image manifest, manifest list, and container config.

  :code:`-s`, :code:`--storage`
    The storage directory for the unpacked image. Defaults:
    :code:`CH_GROW_STORAGE`, :code:`/var/tmp/ch-v2-api`.

  :code:`--version`
    Print version number and exit.
