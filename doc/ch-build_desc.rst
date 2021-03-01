Synopsis
========

::

  $ ch-build [-b BUILDER] [--builder-info] -t TAG [ARGS ...] CONTEXT

Description
===========

Build an image named :code:`TAG` described by a Dockerfile. Place the result
into the builder's back-end storage.

Using this script is *not* required for a working Charliecloud image. You can
also use any builder that can produce a Linux filesystem tree directly,
whether or not it is in the list below. However, this script hides the
vagaries of making the supported builders work smoothly with Charliecloud and
adds some conveniences (e.g., pass HTTP proxy environment variables to the
build environment if the builder doesn't do this by default).

Supported builders, unprivileged:

  * :code:`ch-image`: Our internal builder.

Supported builders, privileged:

  * :code:`docker`: Docker.

Experimental builders (i.e., the code is there but not tested much):

  * :code:`buildah`: Buildah in "rootless" mode with no setuid helpers, using
    :code:`ch-run` (via :code:`ch-run-oci`) for :code:`RUN` instructions. This
    mode is fully unprivileged.

  * :code:`buildah-runc`: Buildah in "rootless" mode with setuid
    helpers, using the default :code:`runc` for :code:`RUN` instructions.

  * :code:`buildah-setuid`: Buildah in "rootless" mode with setuid helpers,
    using :code:`ch-run` (via :code:`ch-run-oci`) for :code:`RUN`
    instructions.

Specifying the builder, in descending order of priority:

  :code:`-b`, :code:`--builder BUILDER`
    Command line option.

  :code:`$CH_BUILDER`
    Environment variable

  Default
    :code:`docker` if Docker is installed; otherwise, :code:`ch-image`.

Other arguments:

  :code:`--builder-info`
    Print the builder to be used and its version, then exit.

  :code:`-f`, :code:`--file DOCKERFILE`
    Dockerfile to use (default: :code:`$CONTEXT/Dockerfile`)

  :code:`-t TAG`
    Name (tag) of Docker image to build.

  :code:`--help`
    Print help and exit.

  :code:`--version`
    Print version and exit.

Additional arguments are accepted and passed unchanged to the underlying
builder.

Bugs
====

The tag suffix :code:`:latest` is somewhat misleading, as by default neither
:code:`ch-build` nor bare builders will notice if the base :code:`FROM` image
has been updated. Use :code:`--pull` to make sure you have the latest base
image.

Examples
========

Create an image tagged :code:`foo` and specified by the file
:code:`Dockerfile` located in the context directory. Use :code:`/bar` as the
Docker context directory. Use the default builder.

::

  $ ch-build -t foo /bar

Equivalent to above::

  $ ch-build -t foo --file=/bar/Dockerfile /bar

Instead, use :code:`/bar/Dockerfile.baz`::

  $ ch-build -t foo --file=/bar/Dockerfile.baz /bar

Equivalent to the first example, but use :code:`ch-image` even if Docker is
installed::

  $ ch-build -b ch-image -t foo /bar

Equivalent to above::

  $ export CH_BUILDER=ch-image
  $ ch-build -t foo /bar
