:code:`ch-convert`
++++++++++++++++++

.. only:: not man

   Convert an image from one format to another.


Synopsis
========

::

  $ ch-convert [-i FMT] [-o FMT] [OPTION ...] IN OUT

Description
===========

Copy image :code:`IN` to :code:`OUT` and convert its format. Replace
:code:`OUT` if it already exists, unless :code:`--no-clobber` is specified. It
is an error if :code:`IN` and :code:`OUT` have the same format; use the
format’s own tools for that case.

:code:`ch-run` can run container images that are plain directories or
(optionally) SquashFS archives. However, images can take on a variety of other
formats as well. The main purpose of this tool is to make images in those
other formats available to :code:`ch-run`.

For best performance, :code:`ch-convert` should be invoked only once,
producing the final format actually needed.

  :code:`IN`
    Descriptor for the input image. For image builders, this is an image
    reference; otherwise, it’s a filesystem path.

  :code:`OUT`
    Descriptor for the output image.

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`-i`, :code:`--in-fmt FMT`
    Input image format is :code:`FMT`. If omitted, inferred as described below.

  :code:`-n`, :code:`--dry-run`
    Don’t read the input or write the output. Useful for testing format
    inference.

  :code:`--no-clobber`
    Error if :code:`OUT` already exists, rather than replacing it.

  :code:`--no-xattrs`
    Ignore xattrs and ACLs when converting.

  :code:`-o`, :code:`--out-fmt FMT`
    Output image format is :code:`FMT`; inferred if omitted.

  :code:`-q`, :code:`--quiet`
    Be quieter; can be repeated. Incompatible with :code:`-v`. See the :ref:`FAQ
    entry on verbosity <faq_verbosity>` for details.

  :code:`-s`, :code:`--storage DIR`
    Set the storage directory. Equivalent to the same option for :code:`ch-image(1)`
    and :code:`ch-run(1)`.

  :code:`--tmp DIR`
    A sub-directory for temporary storage is created in :code:`DIR` and
    removed at the end of a successful conversion. **If this script crashes or
    errors out, the temporary directory is left behind to assist in
    debugging.** Storage may be needed up to twice the uncompressed size of
    the image, depending on the input and output formats. Default:
    :code:`$TMPDIR` if specified; otherwise :code:`/var/tmp`.

  :code:`-v`, :code:`--verbose`
    Print extra chatter. Can be repeated.

.. Notes:

   1. It’s a deliberate choice to use UNIXey options rather than the Skopeo
      syntax [1], e.g. "-i docker" rather than "docker:image-name".

      [1]: https://manpages.debian.org/unstable/golang-github-containers-image/containers-transports.5.en.html

   2. There used to be an [OUT_ARG ...] that would be passed unchanged to the
      archiver, i.e. tar(1) or mksquashfs(1). However it wasn’t clear there
      were real use cases, and this has lots of opportunities to mess things
      up. Also, it’s not clear when it will be called. For example, if you
      convert a directory to a tarball, then passing e.g. -J to XZ-compress
      will work fine, but when converting from Docker, we just compress the
      tarball we got from Docker, so in that case -J wouldn’t work.

   3. I also deliberately left out an option to change the output compression
      algorithm, under the assumption that the default is good enough. This
      can be revisited later IMO if needed.


Image formats
=============

:code:`ch-convert` knows about these values of :code:`FMT`:

  :code:`ch-image`
    Internal storage for Charliecloud’s unprivileged image builder (Dockerfile
    interpreter) :code:`ch-image`.

  :code:`dir`
    Ordinary filesystem directory (i.e., not a mount point) containing an
    unpacked image. Output directories that already exist are replaced if they
    look like an image. If the output directory is empty, the conversion should
    use the directory without overwriting it. If the directory doesn’t look like
    an image and isn’t empty, exit with an error.

  :code:`docker`
    Internal storage for Docker.

  :code:`podman`
    Internal storage for Podman.

  :code:`squash`
    SquashFS filesystem archive containing the flattened image. SquashFS
    archives are much like tar archives but are mountable, including by
    :code:`ch-run`'s internal SquashFUSE mounting. Most systems have at least
    the SquashFS-Tools installed which allows unpacking into a directory, just
    like tar. Due to this greater flexibility, SquashFS is preferred to tar.

    **Note:** Conversions to and from SquashFS are quite noisy due to the
    verbosity of the underlying :code:`mksquashfs(1)` and
    :code:`unsquashfs(1)` tools.

  :code:`tar`
    Tar archive containing the flattened image with no layer sub-archives;
    i.e., the output of :code:`docker export` works but the output of
    :code:`docker save` does not. Output tarballs are always gzipped and must
    end in :code:`.tar.gz`; input tarballs can be any compression acceptable
    to :code:`tar(1)`.

All of these are local formats; :code:`ch-convert` does not know how to push
or pull images.


Format inference
================

:code:`ch-convert` tries to save typing by guessing formats when they are
reasonably clear. This is done against filenames, rather than file contents,
so the rules are the same for output descriptors that do not yet exist.

Format inference is done for both :code:`IN` and :code:`OUT`. The first
matching glob below yields the inferred format. Paths need not exist in the
filesystem.

  1. :code:`*.sqfs`, :code:`*.squash`, :code:`*.squashfs`: SquashFS.

  2. :code:`*.tar`, :code:`*.t?z`, :code:`*.tar.?`, :code:`*.tar.??`: Tarball.

  3. :code:`/*`, :code:`./*`, i.e. absolute path or relative path with
     explicit dot: Directory.

  4. If `ch-image` is installed: :code:`ch-image` internal storage.

  5. If Podman is installed: Podman internal storage.

  6. If Docker is installed: Docker internal storage.

  7. Otherwise: No format inference.

Examples
========

Typical build-to-run sequence for image :code:`foo/bar` using :code:`ch-run`'s
internal SquashFUSE code, inferring the output format::

  $ sudo docker build -t foo/bar -f Dockerfile .
  [...]
  $ ch-convert foo/bar:latest /var/tmp/foobar.sqfs
  input:   docker    foo/bar:latest
  output:  squashfs  /var/tmp/foobar.sqfs
  copying ...
  done
  $ ch-run /var/tmp/foobar.sqfs -- echo hello
  hello

Same conversion, but no format inference::

  $ ch-convert -i ch-image -o squash foo/bar:latest /var/tmp/foobar.sqfs
  input:   docker    foo/bar:latest
  output:  squashfs  /var/tmp/foobar.sqfs
  copying ...
  done


.. include:: ./bugs.rst
.. include:: ./see_also.rst

..  LocalWords:  FMT fmt
