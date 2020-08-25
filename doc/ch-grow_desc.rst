Synopsis
========

::

   $ ch-grow [OPTIONS] [-t TAG] [-f DOCKERFILE] CONTEXT

Description
===========

Build an image named :code:`TAG` as specified in :code:`DOCKERFILE`; use
:code:`ch-run(1)` to execute :code:`RUN` instructions. This builder is
completely unprivileged, with no setuid/setgid/setcap helpers.

:code:`ch-grow` maintains state and temporary images using normal files and
directories. This storage directory can reside on any filesystem, and its
location is configurable. In descending order of priority:

  :code:`-s`, :code:`--storage DIR`
    Command line option.

  :code:`$CH_GROW_STORAGE`
    Environment variable.

  :code:`/var/tmp/$USER/ch-grow`
    Default.

.. note::

   Images are stored unpacked, so place your storage directory on a filesystem
   that can handle the metadata traffic for large numbers of small files. For
   example, the Charliecloud test suite uses approximately 400,000 files and
   directories.

Other arguments:

  :code:`CONTEXT`
    Context directory; this is the root of :code:`COPY` and :code:`ADD`
    instructions in the Dockerfile.

  :code:`--build-arg KEY[=VALUE]`
    Set build-time variable :code:`KEY` defined by :code:`ARG` instruction
    to :code:`VALUE`. If :code:`VALUE` not specified, use the value of
    environment variable :code:`KEY`.

  :code:`--dependencies`
    Report any dependency problems and exit. If all is well, there is no
    output and the exit code is zero; in case of problems, the exit code is
    non-zero.

  :code:`-f`, :code:`--file DOCKERFILE`
    Use :code:`DOCKERFILE` instead of :code:`CONTEXT/Dockerfile`. Specify a
    single hyphen (:code:`-`) to use standard input; note that in this case,
    the context directory is still provided, which matches :code:`docker build
    -f -` behavior.

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`-n`, :code:`--dry-run`
    Do not actually execute any Dockerfile instructions.

  :code:`--no-cache`
    Ignored (:code:`ch-grow` does not yet support layer caching).

  :code:`--parse-only`
    Stop after parsing the Dockerfile.

  :code:`--print-storage`
    Print the storage directory path and exit. Must be after
    :code:`--storage`, if any, for correct results.

  :code:`-t`, :code:`-tag TAG`
    Name of image to create. Append :code:`:latest` if no colon present.

  :code:`-v`, :code:`--verbose`
    Print extra chatter; can be repeated.

  :code:`--version`
    Print version number and exit.

Environment variables
=====================

.. include:: py_env.rst

Conformance
===========

:code:`ch-grow` is an independent implementation and shares no code with other
Dockerfile interpreters. It uses a formal Dockerfile parsing grammar developed
from the `Dockerfile reference documentation
<https://docs.docker.com/engine/reference/builder/>`_ and miscellaneous other
sources, which you can examine in the source code.

We believe this indedendence is valuable for several reasons. First, it helps
the community examine Dockerfile syntax and semantics critically, think
rigorously about what is really needed, and build a more robust standard.
Second, it yields disjoint sets of bugs (note that Podman, Buildah, and Docker
all share the same Dockerfile parser). Third, because it is a much smaller
code base, it illustrates how Dockerfiles work more clearly. Finally, it
allows straightforward extensions if needed to support scientific computing.

:code:`ch-grow` tries hard to be compatible with Docker and other
interpreters, though as an independent implementation, it is not
bug-compatible.

This section describes differences from the Dockerfile reference that we
expect to be approximately permanent. For an overview of features we have not
yet implemented and our plans, see our `road map
<https://github.com/hpc/charliecloud/projects/1>`_ on GitHub. Plain old bugs
are in our `GitHub issues <https://github.com/hpc/charliecloud/issues>`_.

None of these are set in stone. We are very interested in feedback on our
assessments and open questions. This helps us prioritize new features and
revise our thinking about what is needed for HPC containers.

Quirks of a fully unprivileged build
------------------------------------

:code:`ch-grow` is *fully* unprivileged. It runs all instructions as the
normal user who invokes it, does not use any setuid or setcap helper programs,
and does not use :code:`/etc/subuid` or :code:`/etc/subgid`, in contrast to
the “rootless” mode of some competing builders.

:code:`RUN` instructions are executed with :code:`ch-run --uid=0 --gid=0`,
i.e., host EUID and EGID both mapped to zero inside the container, and only
one UID (zero) and GID (zero) are available inside the container. Also,
:code:`/etc/passwd` and :code:`/etc/group` are bind-mounted from temporary
files outside the container and can't be written. (Strictly speaking, the
files themselves are read-write, but because they are bind-mounted, the common
pattern of writing a new file and moving it on top of the existing one fails.)

This has two consequences: the shell and its children appear to be running as
root but only some privileged system calls are available, and manipulating
users and groups will fail. This confuses some programs, which fail with
"permission denied" and related errors; for example, :code:`chgrp(1)` often
appears in Debian package post-install scripts. We have worked around some of
these problems, but many remain. Another manual workaround is to install
:code:`fakeroot` in the Dockerfile and prepend :code:`fakeroot` to problem
commands.

.. note::

   Most of these issues affect *any* fully unprivileged container build, not
   just :code:`ch-grow`. We are working to better characterize the problems
   and add automatic workarounds.

Context directory
-----------------

The context directory is bind-mounted into the build, rather than copied like
Docker. Thus, the size of the context is immaterial, and the build reads
directly from storage like any other local process would. However, you still
can't access anything outside the context directory.

Authentication
--------------

:code:`ch-grow` can authenticate using one-time passwords, e.g. those provided
by a security token. Unlike :code:`docker login`, it does not assume passwords
are persistent.

Environment variables
---------------------

Variable substitution happens for *all* instructions, not just the ones listed
in the Dockerfile reference.

:code:`ARG` and :code:`ENV` cause cache misses upon *definition*, in contrast
with Docker where these variables miss upon *use*, except for certain
cache-excluded variables that never cause misses, listed below.

Like Docker, :code:`ch-grow` pre-defines the following proxy variables, which
do not require an :code:`ARG` instruction. However, they are available if the
same-named environment variable is defined; :code:`--build-arg` is not
required. Changes to these variables do not cause a cache miss.

.. code-block:: sh

   HTTP_PROXY
   http_proxy
   HTTPS_PROXY
   https_proxy
   FTP_PROXY
   ftp_proxy
   NO_PROXY
   no_proxy

The following variables are also pre-defined:

.. code-block:: sh

   PATH=/ch/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
   TAR_OPTIONS=--no-same-owner

Note that :code:`ARG` and :code:`ENV` have different syntax despite very
similar semantics.

:code:`COPY`
------------

Especially for people used to UNIX :code:`cp(1)`, the semantics of the
Dockerfile :code:`COPY` instruction can be confusing.

Most notably, when a source of the copy is a directory, the *contents* of that
directory, not the directory itself, are copied. This is documented, but it's
a real gotcha because that's not what :code:`cp(1)` does, and it means that
many things you can do in one :code:`cp(1)` command require multiple
:code:`COPY` instructions.

Also, the reference documentation is incomplete. In our experience, Docker
also behaves as follows; :code:`ch-grow` does the same in an attempt to be
bug-compatible for the :code:`COPY` instructions.

1. You can use absolute paths in the source; the root is the context
   directory.

2. Destination directories are created if they don't exist in the following
   situations:

   1. If the destination path ends in slash. (Documented.)

   2. If the number of sources is greater than 1, either by wildcard or
      explicitly, regardless of whether the destination ends in slash. (Not
      documented.)

   3. If there is a single source and it is a directory. (Not documented.)

3. Symbolic links are particularly messy (this is not documented):

   1. If named in sources either explicitly or by wildcard, symlinks are
      dereferenced, i.e., the result is a copy of the symlink target, not the
      symlink itself. Keep in mind that directory contents are copied, not
      directories.

   2. If within a directory named in sources, symlinks are copied as symlinks.

We expect the following differences to be permanent:

* Wildcards use Python glob semantics, not the Go semantics.

* :code:`COPY --chown` is ignored, because it doesn't make sense in an
  unprivileged build.

Features we do not plan to support
----------------------------------

* Parser directives are not supported. We have not identified a need for any
  of them.

* :code:`EXPOSE`: Charliecloud does not use the network namespace, so
  containerized processes can simply listen on a host port like other
  unprivileged processes.

* :code:`HEALTHCHECK`: This instruction's main use case is monitoring server
  processes rather than applications. Also, implementing it requires a
  container supervisor daemon, which we have no plans to add.

* :code:`MAINTAINER` is deprecated.

* :code:`STOPSIGNAL` requires a container supervisor daemon process, which we
  have no plans to add.

* :code:`USER` does not make sense for unprivileged builds.

* :code:`VOLUME`: This instruction is not currently supported. Charliecloud
  has good support for bind mounts; we anticipate that it will continue to
  focus on that and will not introduce the volume management features that
  Docker has.
