Synopsis
========

::

   $ ch-tug [OPTIONS] IMAGE_REF

Description
===========

.. warning::

   This script is experimental. Please report the bugs you find so we can fix
   them!

Pull the image described by :code:`IMAGE_REF` from a repository by HTTPS and
flatten it to a local filesystem. The resulting image directory can be used by
:code:`ch-run(1)` or feed into other processing.

This script does a fair amount of validation and fixing of the layer tarballs
before flattening in order to support unprivileged use despite image problems
we frequently see in the wild. For example, device files are ignored, and file
and directory permissions are increased to a minimum of :code:`rwx------` and
:code:`rw-------` respectively. Note, however, that symlinks pointing outside
the image are permitted, because they are not resolved until runtime within a
container.

Typically this script is not used directly. Most tasks instead use the
underlying code during image build with :code:`ch-grow(1)`.

Other arguments:

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`--dependencies`
    Report any dependency problems and exit. If all is well, there is no
    output and the exit code is zero; in case of problems, the exit code is
    non-zero.

  :code:`--dl-cache DIR`
    Use :code:`DIR` to store downloaded layers and metadata. If not specified
    but environment variable :code:`CH_GROW_STORAGE` is, then use
    :code:`$CH_GROW_STORAGE/dlcache`; the default is
    :code:`/var/tmp/ch-grow/dlcache`.

  :code:`--no-cache`
    Always download files, even if they already exist in :code:`--dl-cache`.

  :code:`--image-subdir DIR`
    Subdirectory of :code:`--unpack-dir` to hold the flattened image. Can be
    the empty string, in which case :code:`--unpack-dir` is used directly. The
    default is :code:`IMAGE_REF` with slashes replaced by percent signs.

  :code:`--parse-ref-only`
    Parse :code:`IMAGE_REF`, print a parse report, and exit successfully.

  :code:`--unpack-dir DIR`
    Directory containing flattened images. If not specified but environment
    variable :code:`CH_GROW_STORAGE` is, then use
    :code:`$CH_GROW_STORAGE/img`; the default is :code:`/var/tmp/ch-grow/img`.

  :code:`-v`, :code:`--verbose`
    Print extra chatter; can be repeated.

  :code:`--version`
    Print version number and exit.

Examples
========

Download the classic Docker "hello-world" image and flatten it into
:code:`/var/tmp/ch-grow/img/hello-world`::

  $ ch-tug hello-world
  pulling image: hello-world
  manifest: downloading
  layer 1/1: 1b930d0: downloading
  layer 1/1: 1b930d0: listing
  validating tarball members
  resolving whiteouts
  flattening image
  creating new image: /var/tmp/ch-grow/img/hello-world
  layer 1/1: 1b930d0: extracting
  done
  $ ls /var/tmp/ch-grow/img/hello-world
  hello
  $ ls /var/tmp/ch-grow/dlcache
  1b930d010525941c1d56ec53b97bd057a67ae1865eebf042686d2a2d18271ced.tar.gz
  hello-world.manifest.json

Download the image "charliecloud/whiteout:2020-01-10" and flatten it::

  $ ch-tug charliecloud/whiteout:2020-01-10
  pulling image: charliecloud/whiteout:2020-01-10
  manifest: downloading
  layer 1/86: e7c96db: downloading
  layer 2/86: 4816f76: downloading
  [...]
  layer 85/86: 59b7abe: extracting
  layer 86/86: e756ca6: extracting
  done
  $ ls /var/tmp/ch-grow/img
  charliecloud%whiteout:2020-01-10

Download the "hello-world" image and flatten it into :code:`/tmp/foo`::

  $ ch-tug --unpack-dir=/tmp --image-subdir=foo hello-world
  [...]
  $ ls /tmp/foo
  hello

Same as above::

  $ ch-tug --unpack-dir=/tmp/foo --image-subdir='' hello-world
  [...]
  $ ls /tmp/foo
  hello
