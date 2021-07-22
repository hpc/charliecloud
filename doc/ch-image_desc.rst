Synopsis
========

.. Note: Keep these consistent with the synopses in each subcommand.

::

   $ ch-image [...] build [-t TAG] [-f DOCKERFILE] [...] CONTEXT
   $ ch-image [...] delete IMAGE_REF
   $ ch-image [...] import PATH IMAGE_REF
   $ ch-image [...] list [IMAGE_REF]
   $ ch-image [...] pull [...] IMAGE_REF [IMAGE_DIR]
   $ ch-image [...] push [--image DIR] IMAGE_REF [DEST_REF]
   $ ch-image [...] reset
   $ ch-image [...] storage-path
   $ ch-image { --help | --version | --dependencies }


Description
===========

:code:`ch-image` is a tool for building and manipulating container images, but
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

  :code:`-a`, :code:`--arch ARCH`
     Use :code:`ARCH` for architecture-aware registry operations, currently
     :code:`pull` and pulls done within :code:`build`. :code:`ARCH` can be:
     (1) :code:`yolo`, to bypass architecture-aware code and use the
     registry's default architecture; (2) :code:`host`, to use the host's
     architecture, obtained with the equivalent of :code:`uname -m` (default
     if :code:`--arch` not specified); or (3) an architecture name. If the
     specified architecture is not available, the error message will list
     which ones are.

     **Notes:**

     1. :code:`ch-image` is limited to one image per image reference in
        builder storage at a time, regardless of architecture. For example, if
        you say :code:`ch-image pull --arch=foo baz` and then :code:`ch-image
        pull --arch=bar baz`, builder storage will contain one image called
        "baz", with architecture "bar".

     2. Images' default architecture is usually :code:`amd64`, so this is
        usually what you get with :code:`--arch=yolo`. Similarly, if a
        registry image is architecture-unaware, it will still be pulled with
        :code:`--arch=amd64` and :code:`--arch=host` on x86-64 hosts (other
        host architectures must specify :code:`--arch=yolo` to pull
        architecture-unaware images).

     3. :code:`uname -m` and image registries often use different names for
        the same architecture. For example, what :code:`uname -m` reports as
        "x86_64" is known to registries as "amd64". :code:`--arch=host` should
        translate if needed, but it's useful to know this is happening.
        Directly specified architecture names are passed to the registry
        without translation.

     4. Registries treat architecture as a pair of items, architecture and
        sometimes variant (e.g., "arm" and "v7"). Charliecloud treats
        architecture as a simple string and converts to/from the registry view
        transparently.

  :code:`--no-cache`
    Download everything needed, ignoring the cache.

  :code:`--password-once`
    Re-prompt the user every time a registry password is needed.

  :code:`-s`, :code:`--storage DIR`
    Set the storage directory (see below for important details).

  :code:`--tls-no-verify`
    Don't verify TLS certificates of the repository. (Do not use this option
    unless you understand the risks.)

  :code:`-v`, :code:`--verbose`
    Print extra chatter; can be repeated.

Authentication
==============

If the remote repository needs authentication, Charliecloud will prompt you
for a username and password. Note that some repositories call the secret
something other than "password"; e.g., GitLab calls it a "personal access
token (PAT)".

These values are remembered for the life of the process and silently
re-offered to the registry if needed. One case when this happens is on push to
a private registry: many registries will first offer a read-only token when
:code:`ch-image` checks if something exists, then re-authenticate when
upgrading the token to read-write for upload. If your site uses one-time
passwords such as provided by a security device, you can specify
:code:`--password-once` to provide a new secret each time.

These values are not saved persistently, e.g. in a file. Note that we do use
normal Python variables for this information, without pinning them into
physical RAM with `mlock(2)
<https://man7.org/linux/man-pages/man2/mlock.2.html>`_ or any other special
treatment, so we cannot guarantee they will never reach non-volatile storage.

There is no separate :code:`login` subcommand like Docker. For non-interactive
authentication, you can use environment variables :code:`CH_IMAGE_USERNAME`
and :code:`CH_IMAGE_PASSWORD`. Only do this if you fully understand the
implications for your specific use case, because it is difficult to securely
store secrets in environment variables.

Storage directory
=================

:code:`ch-image` maintains state using normal files and directories, including
unpacked container images, located in its *storage directory*. There is no
notion of storage drivers, graph drivers, etc., to select and/or configure. In
descending order of priority, this directory is located at:

  :code:`-s`, :code:`--storage DIR`
    Command line option.

  :code:`$CH_IMAGE_STORAGE`
    Environment variable.

  :code:`/var/tmp/$USER/ch-image`
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

::

   $ ch-image [...] build [-t TAG] [-f DOCKERFILE] [...] CONTEXT

Build an image from a Dockerfile and put it in the storage directory. Use
:code:`ch-run -w -u0 -g0 --no-home --no-passwd` to execute :code:`RUN`
instructions. Note that :code:`FROM` implicitly pulls the base image if
needed, so you may want to read about the :code:`pull` subcommand below as
well.

Required argument:

  :code:`CONTEXT`
    Path to context directory; this is the root of :code:`COPY` and
    :code:`ADD` instructions in the Dockerfile.

Options:

  :code:`-b`, :code:`--bind SRC[:DST]`
    For :code:`RUN` instructions only, bind-mount :code:`SRC` at guest
    :code:`DST`. The default destination if not specified is to use the same
    path as the host; i.e., the default is equivalent to
    :code:`--bind=SRC:SRC`. If :code:`DST` does not exist, try to create it as
    an empty directory, though images do have ten directories
    :code:`/mnt/[0-9]` already available as mount points. Can be repeated.

    **Note:** See documentation for :code:`ch-run --bind` for important
    caveats and gotchas.

    **Note:** Other instructions that modify the image filesystem, e.g.
    :code:`COPY`, can only access host files from the context directory,
    regardless of this option.

  :code:`--build-arg KEY[=VALUE]`
    Set build-time variable :code:`KEY` defined by :code:`ARG` instruction
    to :code:`VALUE`. If :code:`VALUE` not specified, use the value of
    environment variable :code:`KEY`.

  :code:`-f`, :code:`--file DOCKERFILE`
    Use :code:`DOCKERFILE` instead of :code:`CONTEXT/Dockerfile`. Specify a
    single hyphen (:code:`-`) to use standard input; note that in this case,
    the context directory is still provided, which matches :code:`docker build
    -f -` behavior.

  :code:`--force`
    Inject the unprivileged build workarounds; see discussion later in this
    section for details on what this does and when you might need it. If a
    build fails and :code:`ch-image` thinks :code:`--force` would help, it
    will suggest it.

  :code:`-n`, :code:`--dry-run`
    Don't actually execute any Dockerfile instructions.

  :code:`--no-force-detect`
    Don't try to detect if the workarounds in :code:`--force` would help.

  :code:`--parse-only`
    Stop after parsing the Dockerfile.

  :code:`-t`, :code:`-tag TAG`
    Name of image to create. If not specified, use the final component of path
    :code:`CONTEXT`. Append :code:`:latest` if no colon present.

:code:`ch-image` is a *fully* unprivileged image builder. It does not use any
setuid or setcap helper programs, and it does not use configuration files
:code:`/etc/subuid` or :code:`/etc/subgid`. This contrasts with the “rootless”
or “`fakeroot <https://sylabs.io/guides/3.7/user-guide/fakeroot.html>`_” modes
of some competing builders, which do require privileged supporting code or
utilities.

This approach does yield some quirks. We provide built-in workarounds that
should mostly work (i.e., :code:`--force`), but it can be helpful to
understand what is going on.

:code:`ch-image` executes all instructions as the normal user who invokes it.
For :code:`RUN`, this is accomplished with :code:`ch-run -w --uid=0 --gid=0`
(and some other arguments), i.e., your host EUID and EGID both mapped to zero
inside the container, and only one UID (zero) and GID (zero) are available
inside the container. Under this arrangement, processes running in the
container for each :code:`RUN` *appear* to be running as root, but many
privileged system calls will fail without the workarounds described below.
**This affects any fully unprivileged container build, not just
Charliecloud.**

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

By default, nothing is done to avoid these problems, though :code:`ch-image`
does try to detect if the workarounds could help. :code:`--force` activates
the workarounds: :code:`ch-image` injects extra commands to intercept these
system calls and fake a successful result, using :code:`fakeroot(1)`. There
are three basic steps:

  1. After :code:`FROM`, analyze the image to see what distribution it
     contains, which determines the specific workarounds.

  2. Before the user command in the first :code:`RUN` instruction where the
     injection seems needed, install :code:`fakeroot(1)` in the image, if one
     is not already installed, as well as any other necessary initialization
     commands. For example, we turn off the :code:`apt` sandbox (for Debian
     Buster) and configure EPEL but leave it disabled (for CentOS/RHEL).

  3. Prepend :code:`fakeroot` to :code:`RUN` instructions that seem to need
     it, e.g. ones that contain :code:`apt`, :code:`apt-get`, :code:`dpkg` for
     Debian derivatives and :code:`dnf`, :code:`rpm`, or :code:`yum` for
     RPM-based distributions.

The details are specific to each distribution. :code:`ch-image` analyzes image
content (e.g., grepping :code:`/etc/debian_version`) to select a
configuration; see :code:`lib/fakeroot.py` for details. :code:`ch-image`
prints exactly what it is doing.

:code:`delete`
--------------

::

   $ ch-image [...] delete IMAGE_REF

Delete the image described by the image reference :code:`IMAGE_REF` from the
storage directory.

:code:`list`
------------

Print information about images. If no argument given, list the images in
builder storage.

Optional argument:

  :code:`IMAGE_REF`
    Print details of what's known about :code:`IMAGE_REF`, both locally in the
    remote registry, if any.

:code:`import`
--------------

::

   $ ch-image [...] import PATH IMAGE_REF

Copy the image at :code:`PATH` into builder storage with name
:code:`IMAGE_REF`. :code:`PATH` can be:

* an image directory
* a tarball with no top-level directory (a.k.a. a "`tarbomb <https://en.wikipedia.org/wiki/Tar_(computing)#Tarbomb>`_")
* a standard tarball with one top-level directory

If the imported image contains Charliecloud metadata, that will be imported
unchanged, i.e., images exported from :code:`ch-image` builder storage will be
functionally identical when re-imported.

:code:`pull`
------------

::

   $ ch-image [...] pull [...] IMAGE_REF [IMAGE_DIR]

Pull the image described by the image reference :code:`IMAGE_REF` from a
repository to the local filesystem. See the FAQ for the gory details on
specifying image references.

Destination:

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

This script does a fair amount of validation and fixing of the layer tarballs
before flattening in order to support unprivileged use despite image problems
we frequently see in the wild. For example, device files are ignored, and file
and directory permissions are increased to a minimum of :code:`rwx------` and
:code:`rw-------` respectively. Note, however, that symlinks pointing outside
the image are permitted, because they are not resolved until runtime within a
container.

The following metadata in the pulled image is retained; all other metadata is
currently ignored. (If you have a need for additional metadata, please let us
know!)

  * Current working directory set with :code:`WORKDIR` is effective in
    downstream Dockerfiles.

  * Environment variables set with :code:`ENV` are effective in downstream
    Dockerfiles and also written to :code:`/ch/environment` for use in
    :code:`ch-run --set-env`.

  * Mount point directories specified with :code:`VOLUME` are created in the
    image if they don't exist, but no other action is taken.

Note that some images (e.g., those with a "version 1 manifest") do not contain
metadata. A warning is printed in this case.

:code:`push`
------------

::

   $ ch-image [...] push [--image DIR] IMAGE_REF [DEST_REF]

Push the image described by the image reference :code:`IMAGE_REF` from the
local filesystem to a repository. See the FAQ for the gory details on
specifying image references.

Because Charliecloud is fully unprivileged, the owner and group of files in
its images are not meaningful in the broader ecosystem. Thus, when pushed,
everything in the image is flattened to user:group :code:`root:root`. Also,
setuid/setgid bits are removed, to avoid surprises if the image is pulled by a
privileged container implementation.

Destination:

  :code:`DEST_REF`
    If specified, use this as the destination image reference, rather than
    :code:`IMAGE_REF`. This lets you push to a repository without permanently
    adding a tag to the image.

Options:

  :code:`--image DIR`
    Use the unpacked image located at :code:`DIR` rather than an image in the
    storage directory named :code:`IMAGE_REF`.

:code:`reset`
-------------

::

   $ ch-image [...] reset

Delete all images and cache from ch-image builder storage.

:code:`storage-path`
--------------------

::

   $ ch-image [...] storage-path

Print the storage directory path and exit.

Compatibility with other Dockerfile interpreters
================================================

:code:`ch-image` is an independent implementation and shares no code with
other Dockerfile interpreters. It uses a formal Dockerfile parsing grammar
developed from the `Dockerfile reference documentation
<https://docs.docker.com/engine/reference/builder/>`_ and miscellaneous other
sources, which you can examine in the source code.

We believe this independence is valuable for several reasons. First, it helps
the community examine Dockerfile syntax and semantics critically, think
rigorously about what is really needed, and build a more robust standard.
Second, it yields disjoint sets of bugs (note that Podman, Buildah, and Docker
all share the same Dockerfile parser). Third, because it is a much smaller
code base, it illustrates how Dockerfiles work more clearly. Finally, it
allows straightforward extensions if needed to support scientific computing.

:code:`ch-image` tries hard to be compatible with Docker and other
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

Environment variables
---------------------

Variable substitution happens for *all* instructions, not just the ones listed
in the Dockerfile reference.

:code:`ARG` and :code:`ENV` cause cache misses upon *definition*, in contrast
with Docker where these variables miss upon *use*, except for certain
cache-excluded variables that never cause misses, listed below.

:code:`ch-image` passes the following proxy environment variables in to the
build. Changes to these variables do not cause a cache miss. They do not
require an :code:`ARG` instruction, as `documented
<https://docs.docker.com/engine/reference/builder/#predefined-args>`_ in the
Dockerfile reference. Unlike Docker, they are available if the same-named
environment variable is defined; :code:`--build-arg` is not required.

.. code-block:: sh

   HTTP_PROXY
   http_proxy
   HTTPS_PROXY
   https_proxy
   FTP_PROXY
   ftp_proxy
   NO_PROXY
   no_proxy

In addition to those listed in the Dockerfile reference, these environment
variables are passed through in the same way:

.. code-block:: sh

   SSH_AUTH_SOCK

Finally, these variables are also pre-defined but are unrelated to the host
environment:

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
also behaves as follows; :code:`ch-image` does the same in an attempt to be
bug-compatible.

1. You can use absolute paths in the source; the root is the context
   directory.

2. Destination directories are created if they don't exist in the following
   situations:

   1. If the destination path ends in slash. (Documented.)

   2. If the number of sources is greater than 1, either by wildcard or
      explicitly, regardless of whether the destination ends in slash. (Not
      documented.)

   3. If there is a single source and it is a directory. (Not documented.)

3. Symbolic links behave differently depending on how deep in the copied tree
   they are. (Not documented.)

   1. Symlinks at the top level — i.e., named as the destination or the
      source, either explicitly or by wildcards — are dereferenced. They are
      followed, and whatever they point to is used as the destination or
      source, respectively.

   2. Symlinks at deeper levels are not dereferenced, i.e., the symlink
      itself is copied.

4. If a directory appears at the same path in source and destination, and is
   at the 2nd level or deeper, the source directory's metadata (e.g.,
   permissions) are copied to the destination directory. (Not documented.)

5. If an object appears in both the source and destination, and is at the 2nd
   level or deeper, and is of different types in the source and destination,
   then the source object will overwrite the destination object. (Not
   documented.) For example, if :code:`/tmp/foo/bar` is a regular file, and
   :code:`/tmp` is the context directory, then the following Dockerfile
   snippet will result in a *file* in the container at :code:`/foo/bar`
   (copied from :code:`/tmp/foo/bar`); the directory and all its contents will
   be lost.

     .. code-block:: docker

       RUN mkdir -p /foo/bar && touch /foo/bar/baz
       COPY foo /foo

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

:code:`CH_IMAGE_USERNAME`, :code:`CH_IMAGE_PASSWORD`
  Username and password for registry authentication. **See important caveats
  in section "Authentication" above.**

.. include:: py_env.rst


Examples
========

:code:`build`
-------------

Build image :code:`bar` using :code:`./foo/bar/Dockerfile` and context
directory :code:`./foo/bar`::

   $ ch-image build -t bar -f ./foo/bar/Dockerfile ./foo/bar
   [...]
   grown in 4 instructions: bar

Same, but infer the image name and Dockerfile from the context directory
path::

   $ ch-image build ./foo/bar
   [...]
   grown in 4 instructions: bar

Build using humongous vendor compilers you want to bind-mount instead of
installing into a layer::

   $ ch-image build --bind /opt/bigvendor:/opt .
   $ cat Dockerfile
   FROM centos:7

   RUN /opt/bin/cc hello.c
   #COPY /opt/lib/*.so /usr/local/lib   # fail: COPY doesn't bind mount
   RUN cp /opt/lib/*.so /usr/local/lib  # possible workaround
   RUN ldconfig

:code:`list`
------------

List images in builder storage::

   $ ch-image list
   alpine:3.9 (amd64)
   alpine:latest (amd64)
   debian:buster (amd64)

Print details about Debian Buster image::

   $ ch-image list debian:buster
   details of image:    debian:buster
   in local storage:    no
   full remote ref:     registry-1.docker.io:443/library/debian:buster
   available remotely:  yes
   remote arch-aware:   yes
   host architecture:   amd64
   archs available:     386 amd64 arm/v5 arm/v7 arm64/v8 mips64le ppc64le s390x

:code:`pull`
------------

Download the Debian Buster image matching the host's architecture and place it
in the storage directory::

   $ uname -m
   aarch32
   pulling image:    debian:buster
   requesting arch:  arm64/v8
   manifest list: downloading
   manifest: downloading
   config: downloading
   layer 1/1: c54d940: downloading
   flattening image
   layer 1/1: c54d940: listing
   validating tarball members
   resolving whiteouts
   layer 1/1: c54d940: extracting
   image arch: arm64
   done

Same, specifying the architecture explicitly::

   $ ch-image --arch=arm/v7 pull debian:buster
   pulling image:    debian:buster
   requesting arch:  arm/v7
   manifest list: downloading
   manifest: downloading
   config: downloading
   layer 1/1: 8947560: downloading
   flattening image
   layer 1/1: 8947560: listing
   validating tarball members
   resolving whiteouts
   layer 1/1: 8947560: extracting
   image arch: arm (may not match host arm64/v8)

Download the same image and place it in :code:`/tmp/buster`::

   $ ch-image pull debian:buster /tmp/buster
   [...]
   $ ls /tmp/buster
   bin   dev  home  lib64  mnt  proc  run   srv  tmp  var
   boot  etc  lib   media  opt  root  sbin  sys  usr

:code:`push`
------------

Push a local image to the registry :code:`example.com:5000` at path
:code:`/foo/bar` with tag :code:`latest`. Note that in this form, the local
image must be named to match that remote reference.

::

   $ ch-image push example.com:5000/foo/bar:latest
   pushing image:   example.com:5000/foo/bar:latest
   layer 1/1: gathering
   layer 1/1: preparing
   preparing metadata
   starting upload
   layer 1/1: a1664c4: checking if already in repository
   layer 1/1: a1664c4: not present, uploading
   config: 89315a2: checking if already in repository
   config: 89315a2: not present, uploading
   manifest: uploading
   cleaning up
   done

Same, except use local image :code:`alpine:3.9`. In this form, the local image
name does not have to match the destination reference.

::

   $ ch-image push alpine:3.9 example.com:5000/foo/bar:latest
   pushing image:   alpine:3.9
   destination:     example.com:5000/foo/bar:latest
   layer 1/1: gathering
   layer 1/1: preparing
   preparing metadata
   starting upload
   layer 1/1: a1664c4: checking if already in repository
   layer 1/1: a1664c4: not present, uploading
   config: 89315a2: checking if already in repository
   config: 89315a2: not present, uploading
   manifest: uploading
   cleaning up
   done

Same, except use unpacked image located at :code:`/var/tmp/image` rather than
an image in :code:`ch-image` storage. (Also, the sole layer is already present
in the remote registry, so we don't upload it again.)

::

   $ ch-image push --image /var/tmp/image example.com:5000/foo/bar:latest
   pushing image:   example.com:5000/foo/bar:latest
   image path:      /var/tmp/image
   layer 1/1: gathering
   layer 1/1: preparing
   preparing metadata
   starting upload
   layer 1/1: 892e38d: checking if already in repository
   layer 1/1: 892e38d: already present
   config: 546f447: checking if already in repository
   config: 546f447: not present, uploading
   manifest: uploading
   cleaning up
   done

..  LocalWords:  tmpfs'es bigvendor AUTH
