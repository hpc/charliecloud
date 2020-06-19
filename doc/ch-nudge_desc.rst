Synopsis
========

::

   $ ch-nudge [OPTIONS]

Description
===========

Delete or push image by HTTPS from/to repository. See FAQ for a detailed
description of image reference. Note this script only works with images built
with ch-grow and stored in :code:`CH_GROW_STORAGE` and is typically not used
directly.

:code:`OPTIONS`:

  :code:`delete DEST_IMAGE_REF`
    Delete image :code:`DEST_IMAGE_REF` from repostiory.

  :code:`push IMAGE_REF DEST_IMAGE_REF`
    Push image :code:`IMAGE_REF` to repository :code:`DEST_IMAGE_REF`.

Other arguments:

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`--dependencies`
    Report any dependency problems and exit. If all is well, there is no
    output and the exit code is zero; in case of problems, the exit code is
    non-zero.

  :code:`--unpack-dir DIR`
    Use directory :code:`DIR` for image data. If not specified but environment
    variable :code:`CH_GROW_STORAGE` is, then use
    :code:`$CH_GROW_STORAGE/img`; the default is
    :code:`/var/tmp/$USER/ch-grow/img`.

  :code:`-v`, :code:`--verbose`
    Print extra chatter; can be repeated.

  :code:`--version`
    Print version number and exit.

Examples
========

Push image "hello-world" to the Charliecloud image repository on the Docker
registry.

::

  $ ch-nudge push charliecloud/whiteout:2020-01-10 registry-1.docker.io/charliecloud/whiteout:2020-01-10
  pushing image: whiteout
  [...]

Delete image "hello-world" from the Charliecloud image repository on the
Docker registry.

::

  $ ch-nudge delete registry-1.docker.io:443/charliecloud/hello-world
  deleting image: whiteout
  [...]
