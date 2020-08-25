Synopsis
========

::

   $ ch-nudge [HOSTNAME][:PORT][/PATH/]IMAGE[:TAG]

Description
===========

Push an image via HTTPS to repository. This script only works with images
built with ch-grow.

Push the image :code:`IMAGE[:TAG]` to repository :code:`[HOSTNAME][:PORT]` at
path `[/PATH/]`. Defaults: :code:`registry-1.docker.io:443/library/IMAGE:latest`.

See :code:`ch-grow --list` for a list of availagle images.

:code:`OPTIONS`

  :code:`--delete HOSTNAME[:PORT]/[PATH/]IMAGE[:TAG]`
    Delete image from repository :code:`HOSTNAME[:PORT]` at
    project :code:`[PATH]` with name and tag :code:`IMAGE[:TAG]`

Other arguments:

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`--dependencies`
    Report any dependency problems and exit. If all is well, there is no
    output and the exit code is zero; in case of problems, the exit code is
    non-zero.

  :code:`--storage-dir DIR`
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

Push image "whiteout" to the Charliecloud repository on the Docker registry.

::

  #TODO [...]

Delete image "whiteout" from the Charliecloud repository on the Docker registry.

::

  #TODO [...]
