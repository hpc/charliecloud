Synopsis
========

::

  $ ch-convert [OPTION ...] IN OUT [OUT_ARG ...]

Description
===========

Copy image :code:`IN` to :code:`OUT` and convert its format along the way if
needed. Replace :code:`OUT` if it already exists, unless :code:`--no-clobber`
is specified.

The Charliecloud workflow involves four basic steps:

  1. Build an image using a Dockerfile or pull it from a repository, placing
     the resulting image in *builder storage*.

  2. Convert it to a *packed image*, either a tarball or SquashFS filesystem
     archive.

  3. Make the image available as a directory, either by *mounting* the
     SquashFS filesystem or *unpacking* either type of packed image.

  4. Run a command using the unpacked container image.

Thus, Charliecloud deals with images stored in four different formats:

  1. **Builder storage.** An opaque-to-Charliecloud image format, accessible
     by builder commands such as :code:`docker export`. (Note: Because our
     unprivileged builder :code:`ch-grow` is part of Charliecloud, the details
     of its images are visible to Charliecloud, and in fact that is how they
     are accessed. However, it is often more clear to think of them as opaque
     like the other builders.)

  2. **Tarball.** A tar archive containing the image, possibly compressed. It
     is a flattened image with no layer sub-archives; e.g., the output of
     :code:`docker export` works with Charliecloud but the output of
     :code:`docker save` does not.

  3. **SquashFS.** A SquashFS filesystem archive containing the image.
     SquashFS archives are much like tar archives but can be mounted using
     either kernel code or FUSE. Most systems have at least the SquashFS-Tools
     installed. Due to this greater flexibility, SquashFS is preferred to tar.

  4. **Directory.** A filesystem directory containing an image, typically but
     not necessarily created by unpacking a tarball or SquashFS archive.

(One could imagine a fifth format — the transient, read-only directory created
by mounting a SquashFS archive using :code:`ch-mount(1)` — but that is not an
image *storage* format.)

The purpose of :code:`ch-convert` is to convert images among these four
formats. However, it can also be used to copy images within the same format.

Some copies require temporary storage equal to the uncompressed size of the
image.


Arguments
=========

  :code:`IN`
    Descriptor for the input image. In the case of builder storage, this is an
    image reference; otherwise, a filesystem path.

  :code:`OUT`
    Descriptor for the output image.

  :code:`OUT_ARG ...`
    (Valid only for :code:`tar` and :code:`squash` output formats.) Additional
    arguments passed unchanged to the packing command.

  :code:`-b`, :code:`--builder BUILDER`
    Use image builder :code:`BUILDER`. Default: :code:`$CH_BUILDER` if set;
    otherwise guessed (see :code:`ch-build(1)`).

  :code:`-c`, :code:`--out-compress (none|gzip|xz)`
    (Valid only for :code:`tar` and :code:`squash` output formats.)
    Compression algorithm for archive file. Default: :code:`$CH_COMPRESSION`
    if set; otherwise :code:`gzip`.

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`-i`, :code:`--in-fmt (builder|dir|tar|squash)`
    Format of the input image. If omitted, inferred as described below.

  :code:`--no-clobber`
    Complain and fail if :code:`OUT` already exists, rather than replacing it.

  :code:`-o`, :code:`--out-fmt (builder|dir|tar|squash)`
    Format of the output image; inferred if omitted.

  :code:`-s`, :code:`--builder-storage ARG`
    Some builders take an argument specifying where to find their storage,
    e.g. :code:`ch-grow --storage=/path`. If specified, pass :code:`ARG` to
    the builder. Default: :code:`$CH_GROW_STORAGE` if set; otherwise, see
    :code:`ch-grow(1)`. (Currently only implemented for :code:`ch-grow(1)`.)

  :code:`--tmp DIR`
    Path to temporary directory. Default: :code:`$TMP` if specified; otherwise
    :code:`/tmp`.

  :code:`-v`, :code:`--verbose`
    Print extra chatter.


Format and filename inference
=============================

:code:`ch-convert` tries to save typing by guessing formats and filenames when
they are reasonably clear.

Format inference is done according for both :code:`IN` and :code:`OUT`. The
algorithm tries to match the value agains the following globs in this order.
Paths need not exist in the filesystem.

  1. :code:`*.sqfs`, :code:`*.squash`, :code:`*.squashfs`: SquashFS.
  2. :code:`*.tar`, :code:`*.t?z`, :code:`*.tar.??`, :code:`*.tar.??`: tarball.
  3. :code:`*:*` (i.e., containing a colon): builder storage.
  4. Otherwise: directory.

A notable consequence of these rules is than a simple image reference such as
:code:`debian` is inferred to be a directory. The workaround is to add the
default tag, e.g. :code:`debian:latest`.

:code:`ch-convert` also infers filenames for :code:`OUT` (but not :code:`IN`)
to save typing. If :code:`OUT` is path to a directory that exists, and the
output format is:

  * directory,
    * and :code:`OUT` ends in slash: append inferred filename.
    * otherwise: use :code:`OUT` without modification.
  * tarball or squash: append inferred filename.
  * builder storage: use :code:`OUT` without modification.

Inferred filename rules: FIXME


Supported conversions
=====================

Not all input/output format pairs are supported.

+---------------------+------------------------------------------+
|                     | output                                   |
|                     +---------+---------+----------+-----------+
|                     | builder | tarball | squashfs | directory |
+---------+-----------+---------+---------+----------+-----------+
|         | builder   | p       | Y       | Y        | Y         |
|         +-----------+---------+---------+----------+-----------+
|         | tarball   | p       | Y       | p        | Y         |
| input   +-----------+---------+---------+----------+-----------+
|         | squashfs  | p       | p       | Y        | Y         |
|         +-----------+---------+---------+----------+-----------+
|         | directory | p       | p       | Y        | Y         |
+---------+-----------+---------+---------+----------+-----------+

Key:

  * Y : supported now
  * p: future support is planned
  * *blank* : no plans to support

Note that when converting to builder storage from another format, the output
is a flattened image without layers.


Examples
========

* FIXME
* format inference
* filename inference
  * directory slash/no slash
  * squashfs
* OUT_ARG for squashfs
