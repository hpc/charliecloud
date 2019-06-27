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

  :code:`/var/tmp/ch-grow`
    Default.

.. note::

   Images are stored unpacked, so place sure your storage directory on a
   filesystem that can handle the metadata traffic for large numbers of small
   files. For example, the Charliecloud test suite uses approximately 400,000
   files and directories.

Other arguments:

  :code:`CONTEXT`
    Context directory; this is the root of :code:`COPY` and :code:`ADD`
    instructions in the Dockerfile.

  :code:`-f`, :code:`--file DOCKERFILE`
    Use :code:`DOCKERFILE` instead of :code:`CONTEXT/Dockerfile`.

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`-n`, :code:`--dry-run`
    Do not actually excute any Dockerfile instructions.

  :code:`--parse-only`
    Stop after parsing the Dockerfile.

  :code:`--print-storage`
    Print the storage directory path and exit.

  :code:`-t`, :code:`-tag TAG`
    Name of image to create. Append :code:`:latest` if no colon present.

  :code:`--verbose`
    Print lots of debugging chatter.

  :code:`--version`
    Print version number and exit.

Bugs
====

This script executes :code:`RUN` instructions with host EUID and EGID both
mapped to zero in the container, i.e., with :code:`ch-run --uid=0 gid=0`. This
confuses many programs that appear in :code:`RUN`, which see EUID 0 and/or
EGID 0 and assume they can actually do privileged things, which then fail with
"permission denied" and related errors. For example, :code:`chgrp(1)` often
appears in Debian package post-install scripts. We have worked around some of
these problems, but many remain; please report any you find as bugs.

:code:`COPY` and :code:`ADD` source paths are not restricted to the context
directory. However, because :code:`ch-grow` is completely unprivileged, this
cannot be used to add files not normally readable by the user to the
image.
