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
