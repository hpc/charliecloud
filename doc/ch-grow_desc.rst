Synopsis
========

::

   $ ch-grow [...] build [-t TAG] [-f DOCKERFILE] [...] CONTEXT
   $ ch-grow [...] list
   $ ch-grow [...] pull [...] IMAGE_REF [IMAGE_DIR]
   $ ch-grow [...] storage-path
   $ ch-grow { --help | --version | --dependencies }


Description
===========

:code:`ch-grow` is a tool for building and manipulating container images, but
not running them (for that you want :code:`ch-run`). It is completely
unprivileged, with no setuid/setgid/setcap helpers.

Options that print brief information and then exit:

  :code:`-h`, :code:`--help`
    Print help and exit successfully.

  :code:`--dependencies`
    Report dependency problems on standard output, if any, and exit. If all is
    well, there is no output and the exit is successful; in case of problems,
    the exit is unsuccessful.

  :code:`--version`
    Print version number and exit successfully.

Common options placed before the sub-command:

  :code:`--no-cache`
    Download everything needed, ignoring the cache.

  :code:`-s`, :code:`--storage DIR`
    Set the storage directory (see below for important details).

  :code:`-v`, :code:`--verbose`
    Print extra chatter; can be repeated.


Storage directory
=================

:code:`ch-grow` maintains state using normal files and directories, including
unpacked container images, located in its *storage directory*. There is no
notion of storage drivers, graph drivers, etc., to select and/or configure. In
descending order of priority, this directory is located at:

  :code:`-s`, :code:`--storage DIR`
    Command line option.

  :code:`$CH_GROW_STORAGE`
    Environment variable.

  :code:`/var/tmp/$USER/ch-grow`
    Default.

The storage directory can reside on any filesystem. However, it contains lots
of small files and metadata traffic can be intense. For example, the
Charliecloud test suite uses approximately 400,000 files and directories in
the storage directory as of this writing. Place it on a filesystem appropriate
for this; tmpfs'es such as :code:`/var/tmp` are a good choice if you have
enough RAM (:code:`/tmp` is not recommended because :code:`ch-run` bind-mounts
it into containers by default).

While you can currently poke around in the storage directory and find unpacked
images runnable with :code:`ch-run`, this is not a supported use case. The
supported workflow uses :code:`ch-builder2tar` or :code:`ch-builder2squash` to
obtain a packed image; see the tutorial for details.

.. warning::

   Network filesystems, especially Lustre, are typically bad choices for the
   storage directory. This is a site-specific question and your local support
   will likely have strong opinions.


Subcommands
===========

:code:`build`
-------------

Build an image from a Dockerfile and put it in the storage directory. Use
:code:`ch-run(1)` to execute :code:`RUN` instructions.

Required argument:

  :code:`CONTEXT`
    Path to context directory; this is the root of :code:`COPY` and
    :code:`ADD` instructions in the Dockerfile.

Options:

  :code:`--build-arg KEY[=VALUE]`
    Set build-time variable :code:`KEY` defined by :code:`ARG` instruction
    to :code:`VALUE`. If :code:`VALUE` not specified, use the value of
    environment variable :code:`KEY`.

  :code:`-f`, :code:`--file DOCKERFILE`
    Use :code:`DOCKERFILE` instead of :code:`CONTEXT/Dockerfile`. Specify a
    single hyphen (:code:`-`) to use standard input; note that in this case,
    the context directory is still provided, which matches :code:`docker build
    -f -` behavior.

  :code:`-n`, :code:`--dry-run`
    Don't actually execute any Dockerfile instructions.

  :code:`--no-fakeroot`
    Don't try any of the unprivileged build workarounds (see section "Quirks
    of a fully unprivileged builds" below).

  :code:`--parse-only`
    Stop after parsing the Dockerfile.

  :code:`-t`, :code:`-tag TAG`
    Name of image to create. If not specified, use the final component of path
    :code:`CONTEXT`. Append :code:`:latest` if no colon present.

:code:`storage-path`
--------------------

Print the storage directory path and exit.

:code:`pull`
------------

Pull the image described by the image reference :code:`IMAGE_REF` from a
repository by HTTPS. See the FAQ for the gory details on specifying image
references.

This script does a fair amount of validation and fixing of the layer tarballs
before flattening in order to support unprivileged use despite image problems
we frequently see in the wild. For example, device files are ignored, and file
and directory permissions are increased to a minimum of :code:`rwx------` and
:code:`rw-------` respectively. Note, however, that symlinks pointing outside
the image are permitted, because they are not resolved until runtime within a
container.

Destination argument:

  :code:`IMAGE_DIR`
    If specified, place the unpacked image at this path; it is then ready for
    use by :code:`ch-run` or other tools. The storage directory will not
    contain a copy of the image, i.e., it is only unpacked once.

Options:

  :code:`--last-layer N`
    Unpack only :code:`N` layers, leaving an incomplete image. This option is
    intended for debugging.

  :code:`--parse-only`
    Parse :code:`IMAGE_REF`, print a parse report, and exit successfully
    without talking to the internet or touching the storage directory.


Quirks of a fully unprivileged build
====================================

:code:`ch-grow` is *fully* unprivileged. It runs all instructions as the
normal user who invokes it, does not use any setuid or setcap helper programs,
and does not use :code:`/etc/subuid` or :code:`/etc/subgid`, in contrast to
the “rootless” mode of some competing builders. This is accomplished by
executing :code:`RUN` instructions with :code:`ch-run -w --uid=0 --gid=0` (and
some other arguments), i.e., your host EUID and EGID both mapped to zero
inside the container, and only one UID (zero) and GID (zero) are available
inside the container.

Under this arrangement, processes running in the container *appear* to be
running as root, but many privileged system calls will fail without the
workarounds described below. **This affects any fully unprivileged
container build, not just Charliecloud.**

The most common time to see this is installing packages. For example, here is
RPM failing to :code:`chown(2)` a file, which makes the package update fail:

.. code-block:: none

    Updating   : 1:dbus-1.10.24-13.el7_6.x86_64                            2/4
  Error unpacking rpm package 1:dbus-1.10.24-13.el7_6.x86_64
  error: unpacking of archive failed on file /usr/libexec/dbus-1/dbus-daemon-launch-helper;5cffd726: cpio: chown
    Cleanup    : 1:dbus-libs-1.10.24-12.el7.x86_64                         3/4
  error: dbus-1:1.10.24-13.el7_6.x86_64: install failed

This one is (ironically) :code:`apt-get` failing to drop privileges:

.. code-block:: none

  E: setgroups 65534 failed - setgroups (1: Operation not permitted)
  E: setegid 65534 failed - setegid (22: Invalid argument)
  E: seteuid 100 failed - seteuid (22: Invalid argument)
  E: setgroups 0 failed - setgroups (1: Operation not permitted)

The solution :code:`ch-grow` uses is to intercept these system calls and fake
a successful result. We accomplish this by altering the Dockerfile to call
:code:`fakeroot(1)` (of which there are several implementations) for
:code:`RUN` instructions that seem to need it. There are two basic steps:

  1. After :code:`FROM`, install a :code:`fakeroot(1)` implementation. This
     sometimes also needs extra steps like turning off the :code:`apt` sandbox
     (for Debian Buster) or enabling EPEL (for CentOS/RHEL).

  2. Prepend :code:`fakeroot` to :code:`RUN` instructions that seem to need
     it, e.g. ones that contain :code:`apt`, :code:`apt-get`, :code:`dpkg` for
     Debian derivatives and :code:`dnf`, :code:`rpm`, or :code:`yum` for
     RPM-based distributions.

The details are specific to each distribution. :code:`ch-grow` analyzes image
content (e.g., grepping :code:`/etc/debian_version`) to select a
configuration; see :code:`lib/fakeroot.py` for details. :code:`ch-grow` prints
exactly what it is doing.

To turn off this behavior, use the :code:`--no-fakeroot` option.


Compatibility with other Dockerfile interpreters
================================================

:code:`ch-grow` is an independent implementation and shares no code with other
Dockerfile interpreters. It uses a formal Dockerfile parsing grammar developed
from the `Dockerfile reference documentation
<https://docs.docker.com/engine/reference/builder/>`_ and miscellaneous other
sources, which you can examine in the source code.

We believe this independence is valuable for several reasons. First, it helps
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


Environment variables
=====================

.. include:: py_env.rst


Examples
========

:code:`build`
-------------

Build image :code:`bar` using :code:`./foo/bar/Dockerfile` and context
directory :code:`./foo/bar`::

   $ ch-grow build -t bar -f ./foo/bar/Dockerfile ./foo/bar
   [...]
   grown in 4 instructions: bar

Same, but infer the image name and Dockerfile from the context directory
path::

   $ ch-grow build ./foo/bar
   [...]
   grown in 4 instructions: bar

:code:`pull`
------------

Download the Debian Buster image and place it in the storage directory::

  $ ch-grow pull debian:buster
  pulling image:   debian:buster

  manifest: downloading
  layer 1/1: d6ff36c: downloading
  layer 1/1: d6ff36c: listing
  validating tarball members
  resolving whiteouts
  flattening image
  layer 1/1: d6ff36c: extracting
  done

Same, except place the image in :code:`/tmp/buster`::

   $ ch-grow pull debian:buster /tmp/buster
   [...]
   $ ls /tmp/buster
   bin   dev  home  lib64  mnt  proc  run   srv  tmp  var
   boot  etc  lib   media  opt  root  sbin  sys  usr

..  LocalWords:  tmpfs'es
