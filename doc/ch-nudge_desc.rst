Synopsis
========

::

   $ ch-nudge [OPTIONS] ACTION IMAGE_REF

Description
===========

.. warning::

   This script is experimental. Please report the bugs you find so we can fix
   them!

.. note::
   This script only works with images built with ch-grow stored in
   CH_GROW_STORAGE.

Delete, list, or push image data by HTTPS to repository via :code:`IMAGE_REF`.
Where the image reference :code:`IMAGE_REF` is loosely defind as a string
consisting of a hostname, path, and image. For example,
:code:`HOSTNAME[:PORT]/PATH/[TO/,]/IMAGE[:TAG])`. See examples below and the FAQ
section for more details.

.. note::
   See examples below and FAQ for more details.

Note this script is typically not used directly. Most tasks instead use the
underlying code with :code:`ch-grow(1)`.

:code:`ACTION` must be one of the following:

  :code:`delete IMAGE_REF`
    TODO
  :code:`list IMAGE_REF`
    TODO
  :code:`push IMAGE_REF`
    TODO

Note :code:`IMAGE_REF` is described as ``

Other arguments:

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`--chunk SIZE`
    Upload layer in chunks of size :code:`SIZE`. This is typically unnecessary
    and should be used only by users who are familiar with image uploading and
    why this may useful.

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

  $ ch-nudge push registry-1.docker.io:443/charliecloud/hello-world
  pushing image: hello-world
  [...]

Delete image "hello-world" from the Charliecloud image repository on the
Docker registry.

::

  $ ch-nudge delete registry-1.docker.io:443/charliecloud/hello-world
  deleting image: hello-world
  [...]

List all available tags in the centos repository on the Docker registry.

::

  $ ch-nudge list registry-1.docker.io:443/charliecloud/tags/list
  listing tags
  [...]

List all available repositories from the Docker registry.

::

  $ ch-nudge list registry-1.docker.io:443/_catalog
