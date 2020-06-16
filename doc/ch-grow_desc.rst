Synopsis
========

::

   $ ch-grow [OPTIONS] [-t TAG] [-f DOCKERFILE] CONTEXT

Description
===========

.. warning::

   This script is experimental. Please report the bugs you find so we can fix
   them!

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

Conformance
===========

:code:`ch-grow` is an independent implementation and shares no code with other
Dockerfile interpreters. It uses a formal Dockerfile parsing grammar developed
from the `Dockerfile reference documentation
<https://docs.docker.com/engine/reference/builder/>`_ and miscellaneous other
sources, which you can examine in the source code.

We believe this indedendence is valuable for several reasons. First, it help
the community examine Dockerfile syntax and semantics critically, think
rigorously about what is really needed, and build a more robust standard.
Second, it yields disjoint sets of bugs (note that Podman, Buildah, and Docker
all share the same Dockerfile parser). Third, because it is a much smaller
code base, it illustrates how Dockerfiles work more clearly. Finally, it
allows straightforward extensions if needed to support scientific computing.

:code:`ch-grow` tries hard to be compatible with Docker and other
interpreters, though as an independent implementation, it is not
bug-compatible. There are three reasons our semantics may differ from other
interpreters in any given case:

1. We have not yet implemented something.
2. We believe something is not needed for HPC containers and have left it out
   deliberately.
3. We have made a mistake (i.e., there's a bug).

This section describes known differences from the Dockerfile reference. It is
organized to parallel this reference, with the same headings, to ease
comparison. We have tried to be clear about what is Case 1 vs. Case 2, along
with our future plans. Case 3 differences are typically not listed here, but
our GitHub issues page lists known bugs.

We are very interested in feedback on our assessments and open questions. This
helps us prioritize new features and revise our thinking about what is needed
for HPC containers.

Usage
-----

The context directory is bind-mounted into the build, rather than copied like
Docker. Thus, the size of the context is immaterial, and the build reads
directly from storage like any other local process would.

URL contexts are not supported. We have not yet decided whether to implement
this.

If the Dockerfile is presented on standard input, i.e. with :code:`-f -`,
:code:`ch-grow` still requires a build context. There is not currently a way
to have no context directory.

There is not yet a build cache; each instruction will be re-run each time you
build. However, base images are not re-downloaded or re-built if they're
already present.

Format
------

Comments within a command are not supported. For example:

.. code-block:: dockerfile

   RUN    echo hello \
   # lolcopter
       && echo world

will print "hello world" in Docker but is a syntax error in :code:`ch-grow`.
We are interested in feedback on whether this is useful.

Parser directives
-----------------

So far, we have not identified a need for any of the parser directives, so
they are not supported and we are not planning support.

Environment replacement
-----------------------

In all instructions except for the shell form of :code:`RUN`, substitution of
variables set with :code:`ARG` and :code:`ENV` with :code:`$foo` and
:code:`${foo}` syntaxes is supported, as is escaping with backslash to prevent
substitution.

The :code:`${foo:-bar}` and :code:`${foo:+bar}` modifiers are not yet
supported. Also, we do only one cycle of substitition, so if the substituted
text also contains variables, they will not be substituted; we have no current
plans to change this.

For the shell form of :code:`RUN`, we delegate substitution to the shell, so
you get whatever semantics the shell uses (though see section :code:`SHELL`
below).

Substitution happens for *all* instructions, not just the ones listed in the
reference, which we do not plan to change.

Substitution of variables set in base images is not yet supported.

While :code:`ch-grow` does not yet have a build cache, our plan is that
:code:`ARG` and :code:`ENV` will cause a cache miss upon *definition*, in
contrast with Docker where the variables miss upon *use*, except for certain
cache-excluded variables that never cause misses.

:code:`.dockerignore` file
--------------------------

The :code:`.dockerignore` file is not yet supported.

:code:`FROM`
------------

Base images both in :code:`ch-grow` builder storage as well as remote
repositories are supported. Some image repositories we haven't tested may not
work. Please report these bugs!

If the base image requires authentication, :code:`ch-grow` will prompt for
username and password. Saving credentials (like :code:`docker login`) is not
yet supported.

The :code:`--platform` option is not yet supported.

:code:`ARG` before :code:`FROM` is not yet supported.

Multi-stage build is not yet supported. The syntax :code:`AS foo` is accepted
but ignored.

:code:`RUN`
-----------

:code:`ch-grow` is fully unprivileged. It executes :code:`RUN` instructions
with :code:`ch-run --uid=0 gid=0`, i.e., host EUID and EGID both mapped to
zero inside the container, and only one UID (zero) and GID (zero) are
available inside the container. Also, :code:`/etc/passwd` and
:code:`/etc/group` are bind-mounted from temporary files outside the container
and can't be written. (Strictly speaking, the files themselves are read-write,
but because they are bind-mounted, the common pattern of writing a new file
and moving it on top of the existing one fails.)

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
   just :code:`ch-grow`. This is the bleeding edge. We are working to better
   characterize the problems and add automatic workarounds.

:code:`CMD`
-----------

Neither :code:`CMD` nor :code:`ENTRYPOINT` are currently supported. See the
discussion under :code:`ENTRYPOINT` below.

:code:`LABEL`
-------------

This instruction is not yet supported.

:code:`MAINTAINER`
------------------

We have no plans to support this instruction, because it is deprecated.

:code:`EXPOSE`
--------------

Charliecloud does not use the network namespace, so containerized processes
can simply listen on a host port like other unprivileged processes. We have no
plans to support this instruction.

:code:`ENV`
-----------

See section “Environment replacement” above.

Note that :code:`ENV` and :code:`ARG` have different syntax despite very
similar purposes.

:code:`ADD`
-----------

This instruction is not currently supported, and we have tentatively assigned
it a low priority because Docker Inc.'s best practices discourage its use and
there are workarounds.

We expect that :code:`ADD --chown` will never be supported because it doesn't
make sense in an unprivileged build.

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

The following :code:`COPY` features are not yet implemented:

* From prior stage by index or name, because multi-stage build is not yet
  implemented.

* From an arbitrary image by name.

* List form of the instruction.

* Escaping special characters in filenames.

* :code:`COPY` with Dockerfile on standard input (e.g., :code:`ch-grow -f -`)
  *does* work, because :code:`ch-grow` currently requires a context directory
  in this case (see “Usage” above).

We expect the following differences to be permanent:

* Wildcards use Python glob semantics, not the Go semantics.

* :code:`COPY --chown` is ignored, because it doesn't make sense in an
  unprivileged build.

:code:`ENTRYPOINT`
------------------

Neither :code:`CMD` nor :code:`ENTRYPOINT` are currently supported. This is
for two main reasons:

1. It seemed to us the main use case was for these instructions was containers
   that had a single dominant command line, but we guessed that scientific
   codes would have more variation in the commands run.

2. They are complex instructions, which complex interactions; see the length
   of the :code:`ENTRYPOINT` documentation, especially the matrix of
   interactions with :code:`CMD`.

We are interested in feedback on what we should do.

:code:`VOLUME`
--------------

This instruction is not currently supported. Charliecloud has good support for
bind mounts; we anticipate that it will continue to focus on that and will not
introduce the volume management features that Docker has.

:code:`USER`
------------

We do not plan to support this instruction, because it does not make sense for
unprivileged builds.

:code:`WORKDIR`
---------------

Relative paths are not yet supported.

:code:`ARG`
-----------

See section “Environment replacement” above.

:code:`ARG` before :code:`FROM` is not yet supported.

Like Docker, :code:`ch-grow` pre-defines the following proxy variables, which
do not require an :code:`ARG` instruction. However, they are available if the
same-named environment variable is defined; :code:`--build-arg` is not
required.

.. code-block:: sh

   HTTP_PROXY
   http_proxy
   HTTPS_PROXY
   https_proxy
   FTP_PROXY
   ftp_proxy
   NO_PROXY
   no_proxy

Charliecloud does not currently have an equivalent of :code:`docker history`,
but we do plan to also leave the proxy variables out if/when we do grow one.

The following variables are also pre-defined:

.. code-block:: sh

   PATH=/ch/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
   TAR_OPTIONS=--no-same-owner

Charliecloud does not yet pre-define the “platform :code:`ARG`\ s”.

Note that :code:`ARG` and :code:`ENV` have different syntax despite very
similar purposes.

:code:`ONBUILD`
---------------

This instruction is not currently supported. We have not yet decided whether
to support it in the future.

:code:`STOPSIGNAL`
------------------

We have no plans to support this instruction, because it requires a container
supervisor daemon process, which we have no plans to add.

:code:`HEALTHCHECK`
-------------------

We have no plans to support this instruction, because its main use case is
monitoring server processes rather than applications. Also, implementing it
requires a container supervisor daemon, which we have no plans to add.

:code:`SHELL`
-------------

This instruction is not yet implemented.
