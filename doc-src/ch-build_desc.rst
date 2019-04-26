Synopsis
========

::

  $ ch-build [-b buildah|docker] -t TAG [ARGS ...] CONTEXT

Description
===========

Build an image named :code:`TAG` described by a Dockerfile (default
:code:`./Dockerfile`) using the specified image builder. Place the result into
the builder's backend storage.

Supported builders:

  * Buildah (:code:`buildah build-using-dockerfile` a.k.a. :code:`buildah bud`)
  * Docker (:code:`docker build`)

Arguments:

  :code:`-b`, :code:`--builder`
    Builder to use; one of :code:`buildah` or :code:`docker`. If the option is
    not specified, use the value of environment variable :code:`CH_BUILDER`.
    If neither are specified, try builders in the above order (alphabetical)
    and use the first one in :code:`$PATH`.

  :code:`--builder-info`
    Print the builder to be used and its version, then exit.

  :code:`-f`, :code:`--file`
    Dockerfile to use (default: :code:`./Dockerfile`). Note that calling your
    Dockerfile anything other than :code:`Dockerfile` will confuse people.


  :code:`-t TAG`
    name (tag) of image to build

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Additional arguments are passed unchanged to the underlying builder.

Key improvements over unwrapped builders
========================================

Using :code:`ch-build` is not required; you can also use the builders
directly. However, this command hides the vagaries of making the builders work
smoothly with Charliecloud and adds some conveniences. These improvements
include:

* Pass HTTP proxy environment variables into the build environment.

* If there is a file :code:`Dockerfile` in the current working directory and
  :code:`-f` is not already specified, add :code:`-f $PWD/Dockerfile`.

* (Buildah only.) Use :code:`ch-run-oci` instead of the default :code:`runc`
  to execute :code:`RUN` steps.

Bugs
====

The tag suffix :code:`:latest` is somewhat misleading, as by default neither
:code:`ch-build` nor bare builders will notice if the base :code:`FROM` image
has been updated. Use :code:`--pull` to make sure you have the latest base
image.

Examples
========

Create an image tagged :code:`foo` and specified by the file
:code:`Dockerfile` located in the current working directory. Use :code:`/bar`
as the Docker context directory. Use whatever builder is available.

::

  $ ch-build -t foo /bar

Equivalent to above::

  $ ch-build -t foo --file=./Dockerfile /bar

Instead, use the Dockerfile :code:`/bar/Dockerfile.baz`::

  $ ch-build -t foo --file=/bar/Dockerfile.baz /bar

Equivalent to the first example, but use Buildah (or error if :code:`buildah`
is not in your path)::

  $ ch-build -b buildah -t foo /bar

Equivalent to above::

  $ export CH_BUILDER=buildah
  $ ch-build -t foo /bar
