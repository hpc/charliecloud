:code:`ch-image`
++++++++++++++++

.. only:: not man

   Build and manage images; completely unprivileged.


Synopsis
========

.. Note: Keep these consistent with the synopses in each subcommand.

::

   $ ch-image [...] build [-t TAG] [-f DOCKERFILE] [...] CONTEXT
   $ ch-image [...] build-cache [...]
   $ ch-image [...] delete IMAGE_GLOB [IMAGE_GLOB ...]
   $ ch-image [...] gestalt [SELECTOR]
   $ ch-image [...] import PATH IMAGE_REF
   $ ch-image [...] list [-l] [IMAGE_REF]
   $ ch-image [...] pull [...] IMAGE_REF [DEST_REF]
   $ ch-image [...] push [--image DIR] IMAGE_REF [DEST_REF]
   $ ch-image [...] reset
   $ ch-image [...] undelete IMAGE_REF
   $ ch-image { --help | --version | --dependencies }


Description
===========

:code:`ch-image` is a tool for building and manipulating container images, but
not running them (for that you want :code:`ch-run`). It is completely
unprivileged, with no setuid/setgid/setcap helpers. Many operations can use
caching for speed. The action to take is specified by a sub-command.

Options that print brief information and then exit:

  :code:`-h`, :code:`--help`
    Print help and exit successfully. If specified before the sub-command,
    print general help and list of sub-commands; if after the sub-command,
    print help specific to that sub-command.

  :code:`--dependencies`
    Report dependency problems on standard output, if any, and exit. If all is
    well, there is no output and the exit is successful; in case of problems,
    the exit is unsuccessful.

  :code:`--version`
    Print version number and exit successfully.

Common options placed before or after the sub-command:

  :code:`-a`, :code:`--arch ARCH`
    Use :code:`ARCH` for architecture-aware registry operations. (See section
    "Architecture" below for details.)

  :code:`--always-download`
    Download all files when pulling, even if they are already in builder
    storage. Note that :code:`ch-image pull` will always retrieve the most
    up-to-date image; this option is mostly for debugging.

  :code:`--auth`
    Authenticate with the remote repository, then (if successful) make all
    subsequent requests in authenticated mode. For most subcommands, the
    default is to never authenticate, i.e., make all requests anonymously. The
    exception is :code:`push`, which implies :code:`--auth`.

  :code:`--cache`
    Enable build cache. Default if a sufficiently new Git is available. See
    section :ref:`Build cache <ch-image_build-cache>` for details.

  :code:`--cache-large SIZE`
    Set the cache’s large file threshold to :code:`SIZE` MiB, or :code:`0` for
    no large files, which is the default. Values greater than zero can speed
    up many builds but can also cause performance degradation.
    **Experimental.** See section :ref:`Large file threshold
    <ch-image_bu-large>` for details.

  :code:`--debug`
    Add a stack trace to fatal error hints. This can also be done by setting
    the environment variable :code:`CH_IMAGE_DEBUG`.

  :code:`--no-cache`
    Disable build cache. Default if a sufficiently new Git is not available.
    This option turns off the cache completely; if you want to re-execute a
    Dockerfile and store the new results in cache, use :code:`--rebuild`
    instead.

  :code:`--no-lock`
    Disable storage directory locking. This lets you run as many concurrent
    :code:`ch-image` instances as you want against the same storage directory,
    which risks corruption but may be OK for some workloads.

  :code:`--no-xattrs`
    Enforce default handling of xattrs, i.e. do not save them in the build cache
    or restore them on rebuild. This is the default, but the option is provided
    to override the :code:`$CH_XATTRS` environment variable.

  :code:`--password-many`
    Re-prompt the user every time a registry password is needed.

  :code:`--profile`
    Dump profile to files :code:`/tmp/chofile.p` (:code:`cProfile` dump
    format) and :code:`/tmp/chofile.txt` (text summary). You can convert the
    former to a PDF call graph with :code:`gprof2dot -f pstats /tmp/chofile.p
    | dot -Tpdf -o /tmp/chofile.pdf`. This excludes time spend in
    subprocesses. Profile data should still be written on fatal errors, but
    not if the program crashes.

  :code:`-q, --quiet`
    Be quieter; can be repeated. Incompatible with :code:`-v` and suppresses
    :code:`--debug` regardless of option order. See the :ref:`FAQ entry on
    verbosity <faq_verbosity>` for details.

  :code:`--rebuild`
    Execute all instructions, even if they are build cache hits, except for
    :code:`FROM` which is retrieved from cache on hit.

  :code:`-s`, :code:`--storage DIR`
    Set the storage directory (see below for important details).

  :code:`--tls-no-verify`
    Don’t verify TLS certificates of the repository. (Do not use this option
    unless you understand the risks.)

  :code:`-v`, :code:`--verbose`
    Print extra chatter; can be repeated. See the :ref:`FAQ entry on verbosity
    <faq_verbosity>` for details.

  :code:`--xattrs`
    Save xattrs and ACLs in the build cache, and restore them when rebuilding
    from the cache.


Architecture
============

Charliecloud provides the option :code:`--arch ARCH` to specify the
architecture for architecture-aware registry operations. The argument
:code:`ARCH` can be: (1) :code:`yolo`, to bypass architecture-aware code and
use the registry’s default architecture; (2) :code:`host`, to use the host’s
architecture, obtained with the equivalent of :code:`uname -m` (default if
:code:`--arch` not specified); or (3) an architecture name. If the specified
architecture is not available, the error message will list which ones are.

**Notes:**

1. :code:`ch-image` is limited to one image per image reference in
   builder storage at a time, regardless of architecture. For example, if
   you say :code:`ch-image pull --arch=foo baz` and then :code:`ch-image
   pull --arch=bar baz`, builder storage will contain one image called
   "baz", with architecture "bar".

2. Images’ default architecture is usually :code:`amd64`, so this is
   usually what you get with :code:`--arch=yolo`. Similarly, if a
   registry image is architecture-unaware, it will still be pulled with
   :code:`--arch=amd64` and :code:`--arch=host` on x86-64 hosts (other
   host architectures must specify :code:`--arch=yolo` to pull
   architecture-unaware images).

3. :code:`uname -m` and image registries often use different names for
   the same architecture. For example, what :code:`uname -m` reports as
   "x86_64" is known to registries as "amd64". :code:`--arch=host` should
   translate if needed, but it’s useful to know this is happening.
   Directly specified architecture names are passed to the registry
   without translation.

4. Registries treat architecture as a pair of items, architecture and
   sometimes variant (e.g., "arm" and "v7"). Charliecloud treats
   architecture as a simple string and converts to/from the registry view
   transparently.


Authentication
==============

Charliecloud does not have configuration files; thus, it has no separate
:code:`login` subcommand to store secrets. Instead, Charliecloud will prompt
for a username and password when authentication is needed. Note that some
repositories refer to the secret as something other than a "password"; e.g.,
GitLab calls it a "personal access token (PAT)", Quay calls it an "application
token", and nVidia NGC calls it an "API token".

For non-interactive authentication, you can use environment variables
:code:`CH_IMAGE_USERNAME` and :code:`CH_IMAGE_PASSWORD`. Only do this if you
fully understand the implications for your specific use case, because it is
difficult to securely store secrets in environment variables.

By default for most subcommands, all registry access is anonymous. To instead
use authenticated access for everything, specify :code:`--auth` or set the
environment variable :code:`$CH_IMAGE_AUTH=yes`. The exception is
:code:`push`, which always runs in authenticated mode. Even for pulling public
images, it can be useful to authenticate for registries that have per-user
rate limits, such as `Docker Hub
<https://docs.docker.com/docker-hub/download-rate-limit/>`_. (Older versions
of Charliecloud started with anonymous access, then tried to upgrade to
authenticated if it seemed necessary. However, this turned out to be brittle;
see issue `#1318 <https://github.com/hpc/charliecloud/issues/1318>`_.)

The username and password are remembered for the life of the process and
silently re-offered to the registry if needed. One case when this happens is
on push to a private registry: many registries will first offer a read-only
token when :code:`ch-image` checks if something exists, then re-authenticate
when upgrading the token to read-write for upload. If your site uses one-time
passwords such as provided by a security device, you can specify
:code:`--password-many` to provide a new secret each time.

These values are not saved persistently, e.g. in a file. Note that we do use
normal Python variables for this information, without pinning them into
physical RAM with `mlock(2)
<https://man7.org/linux/man-pages/man2/mlock.2.html>`_ or any other special
treatment, so we cannot guarantee they will never reach non-volatile storage.

.. admonition:: Technical details

   Most registries use something called `Bearer authentication
   <https://datatracker.ietf.org/doc/html/rfc6750>`_, where the client (e.g.,
   Charliecloud) includes a *token* in the headers of every HTTP request.

   The authorization dance is different from the typical UNIX approach, where
   there is a separate login sequence before any content requests are made.
   The client starts by simply making the HTTP request it wants (e.g., to
   :code:`GET` an image manifest), and if the registry doesn’t like the
   client’s token (or if there is no token because the client doesn’t have one
   yet), it replies with HTTP 401 Unauthorized, but crucially it also provides
   instructions in the response header on how to get a token. The client then
   follows those instructions, obtains a token, re-tries the request, and
   (hopefully) all is well. This approach also allows a client to upgrade a
   token if needed, e.g. when transitioning from asking if a layer exists to
   uploading its content.

   The distinction between Charliecloud’s anonymous mode and authenticated
   modes is that it will only ask for anonymous tokens in anonymous mode and
   authenticated tokens in authenticated mode. That is, anonymous mode does
   involve an authentication procedure to obtain a token, but this
   "authentication" is done anonymously. (Yes, it’s confusing.)

   Registries also often reply HTTP 401 when an image does not exist, rather
   than the seemingly more correct HTTP 404 Not Found. This is to avoid
   information leakage about the existence of images the client is not allowed
   to pull, and it’s why Charliecloud never says an image simply does not
   exist.


Storage directory
=================

:code:`ch-image` maintains state using normal files and directories located in
its *storage directory*; contents include various caches and temporary images
used for building.

In descending order of priority, this directory is located at:

  :code:`-s`, :code:`--storage DIR`
    Command line option.

  :code:`$CH_IMAGE_STORAGE`
    Environment variable. The path must be absolute, because the variable is
    likely set in a very different context than when it’s used, which seems
    error-prone on what a relative path is relative to.

  :code:`/var/tmp/$USER.ch`
    Default. (Previously, the default was :code:`/var/tmp/$USER/ch-image`. If
    a valid storage directory is found at the old default path,
    :code:`ch-image` tries to move it to the new default path.)

Unlike many container implementations, there is no notion of storage drivers,
graph drivers, etc., to select and/or configure.

The storage directory can reside on any single filesystem (i.e., it cannot be
split across multiple filesystems). However, it contains lots of small files
and metadata traffic can be intense. For example, the Charliecloud test suite
uses approximately 400,000 files and directories in the storage directory as
of this writing. Place it on a filesystem appropriate for this; tmpfs’es such
as :code:`/var/tmp` are a good choice if you have enough RAM (:code:`/tmp` is
not recommended because :code:`ch-run` bind-mounts it into containers by
default).

While you can currently poke around in the storage directory and find unpacked
images runnable with :code:`ch-run`, this is not a supported use case. The
supported workflow uses :code:`ch-convert` to obtain a packed image; see the
tutorial for details.

The storage directory format changes on no particular schedule.
:code:`ch-image` is normally able to upgrade directories produced by a given
Charliecloud version up to one year after that version’s release. Upgrades
outside this window and downgrades are not supported. In these cases,
:code:`ch-image` will refuse to run until you delete and re-initialize the
storage directory with :code:`ch-image reset`.

.. warning::

   Network filesystems, especially Lustre, are typically bad choices for the
   storage directory. This is a site-specific question and your local support
   will likely have strong opinions.


.. _ch-image_build-cache:

Build cache
===========

Overview
--------

Subcommands that create images, such as :code:`build` and :code:`pull`, can
use a build cache to speed repeated operations. That is, an image is created
by starting from the empty image and executing a sequence of instructions,
largely Dockerfile instructions but also some others like "pull" and "import".
Some instructions are expensive to execute (e.g., :code:`RUN wget
http://slow.example.com/bigfile` or transferring data billed by the byte), so
it’s often cheaper to retrieve their results from cache instead.

The build cache uses a relatively new Git under the hood; see the installation
instructions for version requirements. Charliecloud implements workarounds for
Git’s various storage limitations, so things like file metadata and Git
repositories within the image should work. **Important exception**: No files
named :code:`.git*` or other Git metadata are permitted in the image’s root
directory.

`Extended attributes <https://man7.org/linux/man-pages/man7/xattr.7.html>`_
(xattrs) are ignored by the build cache by default. Cache support for xattrs
belonging to unprivileged xattr namespaces (e.g. :code:`user`) can be enabled by
specifying the :code:`--xattrs` option or by setting the :code:`CH_XATTRS`
environment variable. If :code:`CH_XATTRS` is set, you override it with
:code:`--no-xattrs`. **Note that extended attributes in privileged xattr
namespaces (e.g. :code:`trusted`) cannot be read by :code:`ch-image` and will
always be lost without warning.**

The cache has three modes: *enabled*, *disabled*, and a hybrid mode called
*rebuild* where the cache is fully enabled for :code:`FROM` instructions, but
all other operations re-execute and re-cache their results. The purpose of
*rebuild* is to do a clean rebuild of a Dockerfile atop a known-good base
image.

Enabled mode is selected with :code:`--cache` or setting
:code:`$CH_IMAGE_CACHE` to :code:`enabled`, disabled mode with
:code:`--no-cache` or :code:`disabled`, and rebuild mode with
:code:`--rebuild` or :code:`rebuild`. The default mode is *enabled* if an
appropriate Git is installed, otherwise *disabled*.

Compared to other implementations
---------------------------------

.. note::

   This section is a lightly edited excerpt from our paper “`Charliecloud’s
   layer-free, Git-based container build cache
   <https://arxiv.org/abs/2309.00166>`_”.

Existing tools such as Docker and Podman implement their build cache with a
layered (union) filesystem such as `OverlayFS
<https://github.com/torvalds/linux/blob/af5f239/Documentation/filesystems/overlayfs.rst>`_
or `FUSE-OverlayFS <https://github.com/containers/fuse-overlayfs/tree/v1.12>`_
and tar archives to represent the content of each layer; this approach is
`standardized by OCI
<https://github.com/opencontainers/image-spec/blob/63b8bd0/spec.md>`_. The
layered cache works, but it has drawbacks in three critical areas:

1. **Diff format.** The tar format is poorly standardized and `not designed
   for diffs <https://www.cyphar.com/blog/post/20190121-ociv2-images-i-tar>`_.
   Notably, tar cannot represent file deletion. The workaround used for OCI
   layers is specially named *whiteout* files, which means the tar archives
   cannot be unpacked by standard UNIX tools and require special
   container-specific processing.

2. **Cache overhead.** Each time a Dockerfile instruction is started, a new
   overlay filesystem is mounted atop the existing layer stack. File metadata
   operations in the instruction then start at the top layer and descend the
   stack until the layer containing the desired file is reached. The cost of
   these operations is therefore proportional to the number of layers, i.e.,
   the number of instructions between the empty root image and the instruction
   being executed. This results in a `best practice
   <https://docs.docker.com/develop/develop-images/dockerfile_best-practices/>`_
   of large, complex instructions to minimize their number, which can conflict
   with simpler, more numerous instructions the user might prefer.

3. **De-duplication.** Identical files on layers with an ancestry relationship
   (i.e., instruction *A* precedes *B* in a build) are stored only once.
   However, identical files on layers without this relationship are stored
   multiple times. For example, if instructions *B* and *B'* both follow *A* —
   perhaps because *B* was modified and the image rebuilt — then any files
   created by both *B* and *B'* will be stored twice.

   Also, similar files are never de-duplicated, regardless of ancestry. For
   example, if instruction *A* creates a file and subsequently instruction *B*
   modifies a single bit in that file, both versions are stored in their
   entirety.

Our Git-based cache addresses the three drawbacks: (1) Git is purpose-built to
store changing directory trees, (2) cache overhead is imposed only at
instruction commit time, and (3) Git de-duplicates both identical and similar
files. Also, it is based on an extremely widely used tool that enjoys development
support from well-resourced actors, in particular on scaling (e.g.,
Microsoft’s large-repository accelerator `Scalar
<https://devblogs.microsoft.com/devops/introducing-scalar/>`_ was recently
`merged into Git
<https://github.blog/2022-10-03-highlights-from-git-2-38/>`_).

In addition to these structural advantages, performance experiments reported in our paper above show that the Git-based approach is as good as (and sometimes better than) overlay-based caches. On build time, the two approaches are broadly similar, with one or the other being faster depending on context. Both had performance problems on NFS. Notably, however, the Git-based cache was much faster for a 129-instruction Dockerfile. On disk usage, the winner depended on the condition. For example, we saw the layered cache storing large sibling layers redundantly; on the other hand, the Git-based cache has some obvious redundancies as well, and one must compact it for full de-duplication benefit. However, Git’s de-duplication was quite effective in some conditions and we suspect will prove even better in more realistic scenarios.

That is, we believe our results show that the Git-based build cache is highly competitive with the layered approach, with no obvious inferiority so far and hints that it may be superior on important dimensions. We have ongoing work to explore these questions in more detail.

De-duplication and garbage collection
-------------------------------------

Charliecloud’s build cache takes advantage of Git’s file de-duplication
features. This operates across the entire build cache, i.e., files are
de-duplicated no matter where in the cache they are found or the relationship
between their container images. Files are de-duplicated at different times
depending on whether they are identical or merely similar.

*Identical* files are de-duplicated at :code:`git add` time; in
:code:`ch-image build` terms, that’s upon committing a successful instruction.
That is, it’s impossible to store two files with the same content in the build
cache. If you try — say with :code:`RUN yum install -y foo` in one Dockerfile
and :code:`RUN yum install -y foo bar` in another, which are different
instructions but both install RPM :code:`foo`’s files — the content is stored
once and each copy gets its own metadata and a pointer to the content, much
like filesystem hard links.

*Similar* files, however, are only de-duplicated during Git’s garbage
collection process. When files are initially added to a Git repository (with
:code:`git add`), they are stored inside the repository as (possibly
compressed) individual files, called *objects* in Git jargon. Upon garbage
collection, which happens both automatically when certain parameters are met
and explicitly with :code:`git gc`, these files are archived and
(re-)compressed together into a single file called a *packfile*. Also,
existing packfiles may be re-written into the new one.

During this process, similar files are identified, and each set of similar
files is stored as one base file plus diffs to recover the others. (Similarity
detection seems to be based primarily on file size.) This *delta* process is
agnostic to alignment, which is an advantage over alignment-sensitive
block-level de-duplicating filesystems. Exception: "Large" files are not
compressed or de-duplicated. We use the Git default threshold of 512 MiB (as
of this writing).

Charliecloud runs Git garbage collection at two different times. First, a
lighter-weight garbage pass runs automatically when the number of loose files
(objects) grows beyond a limit. This limit is in flux as we learn more about
build cache performance, but it’s quite a bit higher than the Git default.
This garbage runs in the background and can continue after the build
completes; you may see Git processes using a lot of CPU.

An important limitation of the automatic garbage is that large packfiles
(again, this is in flux, but it’s several GiB) will not be re-packed, limiting
the scope of similar file detection. To address this, a heavier garbage
collection can be run manually with :code:`ch-image build-cache --gc`. This
will re-pack (and re-write) the entire build cache, de-duplicating all similar
files. In both cases, garbage uses all available cores.

:code:`git build-cache` prints the specific garbage collection parameters in
use, and :code:`-v` can be added for more detail.

.. _ch-image_bu-large:

Large file threshold
--------------------

Because Git uses content-addressed storage, upon commit, it must read in full
all files modified by an instruction. This I/O cost can be a significant
fraction of build time for some images. To mitigate this, regular files larger
than the experimental *large file threshold* are stored outside the Git
repository, somewhat like `Git Large File Storage
<https://git-lfs.github.com/>`_.

:code:`ch-image` copies large files in and out of images at each instruction
commit. It tries to do this with a fast metadata-only copy-on-write operation
called “reflink”, but that is only supported with the right Python version,
Linux kernel version, and filesystem. If unsupported, Charliecloud falls back
to an expensive standard copy, which is likely slower than letting Git deal
with the files. See :ref:`File copy performance <best-practices_file-copy>`
for details.

Every version of a large file is stored verbatim and uncompressed (e.g., a
large file with a one-byte change will be stored in full twice), so Git’s
de-duplication does not apply. *However*, on filesystems with reflink support,
files can share extents (e.g., each of the two files will have its own extent
containing the changed byte, but the rest of the extents will remain shared).
This provides de-duplication between large files images that share ancestry.
Also, unused large files are deleted by :code:`ch-image build-cache --gc`.

A final caveat: Large files in any image with the same path, mode, size, and
mtime (to nanosecond precision if possible) are considered identical, even if
their content is not actually identical (e.g., :code:`touch(1)` shenanigans
can corrupt an image).

Option :code:`--cache-large` sets the threshold in MiB; if not set,
environment variable :code:`CH_IMAGE_CACHE_LARGE` is used; if that is not set
either, the default value :code:`0` indicates that no files are considered
large.

(Note that Git has an unrelated setting called :code:`core.bigFileThreshold`.)

Example
-------

Suppose we have this Dockerfile::

  $ cat a.df
  FROM alpine:3.17
  RUN echo foo
  RUN echo bar

On our first build, we get::

  $ ch-image build -t foo -f a.df .
    1. FROM alpine:3.17
  [ ... pull chatter omitted ... ]
    2. RUN echo foo
  copying image ...
  foo
    3. RUN echo bar
  bar
  grown in 3 instructions: foo

Note the dot after each instruction’s line number. This means that the
instruction was executed. You can also see this by the output of the two
:code:`echo` commands.

But on our second build, we get::

  $ ch-image build -t foo -f a.df .
    1* FROM alpine:3.17
    2* RUN echo foo
    3* RUN echo bar
  copying image ...
  grown in 3 instructions: foo

Here, instead of being executed, each instruction’s results were retrieved
from cache. (Charliecloud uses lazy retrieval; nothing is actually retrieved
until the end, as seen by the "copying image" message.) Cache hit for each
instruction is indicated by an asterisk (:code:`*`) after the line number.
Even for such a small and short Dockerfile, this build is noticeably faster
than the first.

We can also try a second, slightly different Dockerfile. Note that the first
three instructions are the same, but the third is different::

  $ cat c.df
  FROM alpine:3.17
  RUN echo foo
  RUN echo qux
  $ ch-image build -t c -f c.df .
    1* FROM alpine:3.17
    2* RUN echo foo
    3. RUN echo qux
  copying image ...
  qux
  grown in 3 instructions: c

Here, the first two instructions are hits from the first Dockerfile, but the
third is a miss, so Charliecloud retrieves that state and continues building.

We can also inspect the cache::

  $ ch-image build-cache --tree
  *  (c) RUN echo qux
  | *  (a) RUN echo bar
  |/
  *  RUN echo foo
  *  (alpine+3.9) PULL alpine:3.17
  *  (root) ROOT

  named images:     4
  state IDs:        5
  commits:          5
  files:          317
  disk used:        3 MiB

Here there are four named images: :code:`a` and :code:`c` that we built, the
base image :code:`alpine:3.17` (written as :code:`alpine+3.9` because colon is
not allowed in Git branch names), and the empty base of everything
:code:`root`. Also note how :code:`a` and :code:`c` diverge after the last
common instruction :code:`RUN echo foo`.


:code:`build`
=============

Build an image from a Dockerfile and put it in the storage directory.

Synopsis
--------

::

   $ ch-image [...] build [-t TAG] [-f DOCKERFILE] [...] CONTEXT

Description
-----------

See below for differences with other Dockerfile interpreters. Charliecloud
supports an extended instruction (:code:`RSYNC`), a few other instructions
behave slightly differently, and a few are ignored.

Note that :code:`FROM` implicitly pulls the base image if needed, so you may
want to read about the :code:`pull` subcommand below as well.

Required argument:

  :code:`CONTEXT`
    Path to context directory. This is the root of :code:`COPY` instructions
    in the Dockerfile. If a single hyphen (:code:`-`) is specified: (a) read
    the Dockerfile from standard input, (b) specifying :code:`--file` is an
    error, and (c) there is no context, so :code:`COPY` will fail. (See
    :code:`--file` for how to provide the Dockerfile on standard input while
    also having a context.)

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
    Use :code:`DOCKERFILE` instead of :code:`CONTEXT/Dockerfile`. If a single
    hyphen (:code:`-`) is specified, read the Dockerfile from standard input;
    like :code:`docker build`, the context directory is still available in
    this case.

  :code:`--force[=MODE]`
    Use unprivileged build with root emulation mode :code:`MODE`, which can be
    :code:`fakeroot`, :code:`seccomp` (the default), or :code:`none`. See
    section “Privilege model” below for details on what this does and when you
    might need it.

  :code:`--force-cmd=CMD,ARG1[,ARG2...]`
    If command :code:`CMD` is found in a :code:`RUN` instruction, add the
    comma-separated :code:`ARGs` to it. For example,
    :code:`--force-cmd=foo,-a,--bar=baz` would transform :code:`RUN foo -c`
    into :code:`RUN foo -a --bar=baz -c`. This is intended to suppress
    validation that defeats :code:`--force=seccomp` and implies that option.
    Can be repeated. If specified, replaces (does not extend) the default
    suppression options. Literal commas can be escaped with backslash;
    importantly however, backslash will need to be protected from the shell
    also. Section “Privilege model” below explains why you might need this.

  :code:`-n`, :code:`--dry-run`
    Don’t actually execute any Dockerfile instructions.

  :code:`--parse-only`
    Stop after parsing the Dockerfile.

  :code:`-t`, :code:`--tag TAG`
    Name of image to create. If not specified, infer the name:

    1. If Dockerfile named :code:`Dockerfile` with an extension: use the
       extension with invalid characters stripped, e.g.
       :code:`Dockerfile.@FOO.bar` → :code:`foo.bar`.

    2. If Dockerfile has extension :code:`df` or :code:`dockerfile`: use the
       basename with the same transformation, e.g. :code:`baz.@QUX.dockerfile`
       -> :code:`baz.qux`.

    3. If context directory is not :code:`/`: use its name, i.e. the last
       component of the absolute path to the context directory, with the same
       transformation,

    4. Otherwise (context directory is :code:`/`): use :code:`root`.

    If no colon present in the name, append :code:`:latest`.

Uses :code:`ch-run -w -u0 -g0 --no-passwd --unsafe` to execute :code:`RUN`
instructions.

Privilege model
---------------

Overview
~~~~~~~~

:code:`ch-image` is a *fully* unprivileged image builder. It does not use any
setuid or setcap helper programs, and it does not use configuration files
:code:`/etc/subuid` or :code:`/etc/subgid`. This contrasts with the “rootless”
or “`fakeroot <https://sylabs.io/guides/3.7/user-guide/fakeroot.html>`_” modes
of some competing builders, which do require privileged supporting code or
utilities.

Without root emulation, this approach does confuse programs that expect to have
real root privileges, most notably distribution package installers. This
subsection describes why that happens and what you can do about it.

:code:`ch-image` executes all instructions as the normal user who invokes it.
For :code:`RUN`, this is accomplished with :code:`ch-run` arguments including
:code:`-w --uid=0 --gid=0`. That is, your host EUID and EGID are both mapped to
zero inside the container, and only one UID (zero) and GID (zero) are available
inside the container. Under this arrangement, processes running in the container
for each :code:`RUN` *appear* to be running as root, but many privileged system
calls will fail without the root emulation methods described below. **This
affects any fully unprivileged container build, not just Charliecloud.**

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

Charliecloud provides two different mechanisms to avoid these problems. Both
involve lying to the containerized process about privileged system calls, but
at very different levels of complexity.

Root emulation mode :code:`fakeroot`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This mode uses :code:`fakeroot(1)` to maintain an elaborate web of deceit that
is internally consistent. This program intercepts both privileged system calls
(e.g., :code:`setuid(2)`) as well as other system calls whose return values
depend on those calls (e.g., :code:`getuid(2)`), faking success for privileged
system calls (perhaps making no system call at all) and altering return values
to be consistent with earlier fake success. Charliecloud automatically
installs the :code:`fakeroot(1)` program inside the container and then wraps
:code:`RUN` instructions having known privilege needs with it. Thus, this mode
is only available for certain distributions.

The advantage of this mode is its consistency; e.g., careful programs that
check the new UID after attempting to change it will not notice anything
amiss. Its disadvantage is complexity: detailed knowledge and procedures for
multiple Linux distributions.

This mode has three basic steps:

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

:code:`RUN` instructions that *do not* seem to need modification are
unaffected by this mode.

The details are specific to each distribution. :code:`ch-image` analyzes image
content (e.g., grepping :code:`/etc/debian_version`) to select a
configuration; see :code:`lib/force.py` for details. :code:`ch-image` prints
exactly what it is doing.

.. warning::

   Because of :code:`fakeroot` mode’s complexity, we plan to remove it if
   :code:`seccomp` mode performs well enough. If you have a situation where
   :code:`fakeroot` mode works and :code:`seccomp` does not, please let us
   know.

Root emulation mode :code:`seccomp` (default)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This mode uses the kernel’s :code:`seccomp(2)` system call filtering to
intercept certain privileged system calls, do absolutely nothing, and return
success to the program.

Some system calls are quashed regardless of their arguments:
:code:`capset(2)`; :code:`chown(2)` and friends; :code:`kexec_load(2)` (used
to validate the filter itself); ; and :code:`setuid(2)`, :code:`setgid(2)`,
and :code:`setgroups(2)` along with the other system calls that change user or
group. :code:`mknod(2)` and :code:`mknodat(2)` are quashed if they try to
create a device file (e.g., creating FIFOs works normally).

The advantages of this approach is that it’s much simpler, it’s faster, it’s
completely agnostic to libc, and it’s mostly agnostic to distribution. The
disadvantage is that it’s a very lazy liar; even the most cursory consistency
checks will fail, e.g., :code:`getuid(2)` after :code:`setuid(2)`.

While this mode does not provide consistency, it does offer a hook to help
prevent programs asking for consistency. For example, :code:`apt-get -o
APT::Sandbox::User=root` will prevent :code:`apt-get` from attempting to drop
privileges, which `it verifies
<https://salsa.debian.org/apt-team/apt/-/blob/cacdb549/apt-pkg/contrib/fileutl.cc#L3343>`_,
exiting with failure if the correct IDs are not found (which they won’t be
under this approach). This can be expressed with
:code:`--force-cmd=apt-get,-o,APT::Sandbox::User=root`, though this particular
case is built-in and does not need to be specified. The full default
configuration, which is applied regardless of the image distribution, can be
examined in the source file :code:`force.py`. If any :code:`--force-cmd` are
specified, this replaces (rather than extends) the default configuration.

Note that because the substitutions are a simple regex with no knowledge of
shell syntax, they can cause unwanted modifications. For example, :code:`RUN
apt-get install -y apt-get` will be run as :code:`/bin/sh -c "apt-get -o
APT::Sandbox::User=root install -y apt-get -o APT::Sandbox::User=root"`. One
workaround is to add escape syntax transparent to the shell; e.g., :code:`RUN
apt-get install -y a\pt-get`.

This mode executes *all* :code:`RUN` instructions with the :code:`seccomp(2)`
filter and has no knowledge of which instructions actually used the
intercepted system calls. Therefore, the printed “instructions modified”
number is only a count of instructions with a hook applied as described above.

:code:`RUN`  logging
~~~~~~~~~~~~~~~~~~~~

In terminal output, image metadata, and the build cache, the :code:`RUN`
instruction is always logged as :code:`RUN.S`, :code:`RUN.F`, or :code:`RUN.N`.
The letter appended to the instruction reflects the root emulation mode used
during the build in which the instruction was executed. :code:`RUN.S` indicates
:code:`seccomp`, :code:`RUN.F` indicates :code:`fakeroot`, and :code:`RUN.N`
indicates that neither form of root emulation was used (:code:`--force=none`).

Compatibility and behavior differences
--------------------------------------

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

The following subsections describe differences from the Dockerfile reference
that we expect to be approximately permanent. For not-yet-implemented features
and bugs in this area, see `related issues
<https://github.com/hpc/charliecloud/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc+label%3Aimage>`_
on GitHub.

None of these are set in stone. We are very interested in feedback on our
assessments and open questions. This helps us prioritize new features and
revise our thinking about what is needed for HPC containers.

Context directory
~~~~~~~~~~~~~~~~~

The context directory is bind-mounted into the build, rather than copied like
Docker. Thus, the size of the context is immaterial, and the build reads
directly from storage like any other local process would (i.e., it is
reasonable use :code:`/` for the context). However, you still can’t
access anything outside the context directory.

Variable substitution
~~~~~~~~~~~~~~~~~~~~~

Variable substitution happens for *all* instructions, not just the ones listed
in the Dockerfile reference.

:code:`ARG` and :code:`ENV` cause cache misses upon *definition*, in contrast
with Docker where these variables miss upon *use*, except for certain
cache-excluded variables that never cause misses, listed below.

Note that :code:`ARG` and :code:`ENV` have different syntax despite very
similar semantics.

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
   USER

Finally, these variables are also pre-defined but are unrelated to the host
environment:

.. code-block:: sh

   PATH=/ch/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
   TAR_OPTIONS=--no-same-owner

:code:`ARG`
~~~~~~~~~~~

Variables set with :code:`ARG` are available anywhere in the Dockerfile,
unlike Docker, where they only work in :code:`FROM` instructions, and possibly
in other :code:`ARG` before the first :code:`FROM`.

:code:`FROM`
~~~~~~~~~~~~

The :code:`FROM` instruction accepts option :code:`--arg=NAME=VALUE`, which
serves the same purpose as the :code:`ARG` instruction. It can be repeated.

:code:`LABEL`
~~~~~~~~~~~~~

The :code:`LABEL` instruction accepts :code:`key=value` pairs to
add metadata for an image. Unlike Docker, multiline values are not supported;
see issue `#1512 <https://github.com/hpc/charliecloud/issues/1512>`_.
Can be repeated.

:code:`COPY`
~~~~~~~~~~~~

.. note:: The behavior described here matches Docker’s `now-deprecated legacy
          builder
          <https://docs.docker.com/engine/deprecated/#legacy-builder-for-linux-images>`_.
          Docker’s new builder, BuildKit, has different behavior in some
          cases, which we have not characterized.

Especially for people used to UNIX :code:`cp(1)`, the semantics of the
Dockerfile :code:`COPY` instruction can be confusing.

Most notably, when a source of the copy is a directory, the *contents* of that
directory, not the directory itself, are copied. This is documented, but it’s
a real gotcha because that’s not what :code:`cp(1)` does, and it means that
many things you can do in one :code:`cp(1)` command require multiple
:code:`COPY` instructions.

Also, the reference documentation is incomplete. In our experience, Docker
also behaves as follows; :code:`ch-image` does the same in an attempt to be
bug-compatible.

1. You can use absolute paths in the source; the root is the context
   directory.

2. Destination directories are created if they don’t exist in the following
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
   at the 2nd level or deeper, the source directory’s metadata (e.g.,
   permissions) are copied to the destination directory. (Not documented.)

5. If an object (a) appears in both the source and destination, (b) is at the
   2nd level or deeper, and (c) is different file types in source and
   destination, the source object will overwrite the destination object. (Not
   documented.)

We expect the following differences to be permanent:

* Wildcards use Python glob semantics, not the Go semantics.

* :code:`COPY --chown` is ignored, because it doesn’t make sense in an
  unprivileged build.

Features we do not plan to support
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* Parser directives are not supported. We have not identified a need for any
  of them.

* :code:`EXPOSE`: Charliecloud does not use the network namespace, so
  containerized processes can simply listen on a host port like other
  unprivileged processes.

* :code:`HEALTHCHECK`: This instruction’s main use case is monitoring server
  processes rather than applications. Also, it requires a container supervisor
  daemon, which we have no plans to add.

* :code:`MAINTAINER` is deprecated.

* :code:`STOPSIGNAL` requires a container supervisor daemon process, which we
  have no plans to add.

* :code:`USER` does not make sense for unprivileged builds.

* :code:`VOLUME`: Charliecloud
  has good support for bind mounts; we anticipate that it will continue to
  focus on that and will not introduce the volume management features that
  Docker has.

.. _ch-image_rsync:

:code:`RSYNC` (Dockerfile extension)
------------------------------------

.. warning::

   This instruction is experimental and may change or be removed.

Overview
~~~~~~~~

Copying files is often simple but has numerous difficult corner cases, e.g.
when dealing with symbolic or hard links. The standard instruction
:code:`COPY` deals with many of these corner cases differently from other UNIX
utilities, lacks complete documentation, and behaves inconsistently between
different Dockerfile interpreters (e.g., Docker’s legacy builder vs.
BuildKit), as detailed above. On the other hand, :code:`rsync(1)` is an
extremely capable, widely used file copy tool, with detailed options to
specify behavior and 25 years of history dealing with weirdness.

:code:`RSYNC` (also spelled :code:`NSYNC`) is a Charliecloud extension that
gives copying behavior identical to :code:`rsync(1)`. In fact, Charliecloud’s
current implementation literally calls the host’s :code:`rsync(1)` to do the
copy, though this may change in the future. There is no list form of
:code:`RSYNC`.

The two key usage challenges are trailing slashes on paths and symlink
handling. In particular, the default symlink handling seemed reasonable to us,
but you may want something different. See the arguments and examples below.
Importantly, :code:`COPY` is not any less fraught, and you have no choice
about what to do with symlinks.


Arguments
~~~~~~~~~

:code:`RSYNC` takes the same arguments as :code:`rsync(1)`, so refer to its
`man page <https://man7.org/linux/man-pages/man1/rsync.1.html>`_ for a
detailed explanation of all the options (with possible emphasis on its
`symlink options
<https://man7.org/linux/man-pages/man1/rsync.1.html#SYMBOLIC_LINKS>`_).
Sources are relative to the context directory even if they look absolute with
a leading slash. Any globbed sources are processed by :code:`ch-image(1)`
using Python rules, i.e., :code:`rsync(1)` sees the expanded sources with no
wildcards. Relative destinations are relative to the image’s current working
directory, while absolute destinations refer to the image’s root.

For arguments that read input from a file (e.g. :code:`--exclude-from` or
:code:`--files-from`), relative paths are relative to the context directory,
absolute paths refer to the image root, and :code:`-` (standard input) is an
error.

For example,

.. code-block:: docker

   WORKDIR /foo
   RSYNC --foo src1 src2 dst

is translated to (the equivalent of)::

   $ mkdir -p /foo
   $ rsync -@=-1 -AHSXpr --info=progress2 -l --safe-links \
           --foo /context/src1 /context/src2 /storage/imgroot/foo/dst2

Note the extensive default arguments to :code:`rsync(1)`. :code:`RSYNC` takes
a single instruction option beginning with :code:`+` (plus) that is shorthand
for a group of :code:`rsync(1)` options. This single option is one of:

  :code:`+m`
    Preserves metadata and directory structure. Symlinks are skipped *with a
    warning*. Equivalent to all of:

    * :code:`-@=-1`: use nanosecond precision when comparing timestamps.
    * :code:`-A`: preserve ACLs.
    * :code:`-H`: preserve hard link groups.
    * :code:`-S`: preserve file sparseness when possible.
    * :code:`-X`: preserve xattrs in :code:`user.*` namespace.
    * :code:`-p`: preserve permissions.
    * :code:`-r`: recurse into directories.
    * :code:`--info=progress2` (only if stderr is a terminal): show progress
      meter (note `subtleties in interpretation
      <https://unix.stackexchange.com/questions/215271>`_).

  :code:`+l` (default)
    Like :code:`+u`, but *silently skips* “unsafe” symlinks whose target is
    outside the top-of-transfer directory. Preserves:

    * Metadata.

    * Directory structure.

    * Symlinks, if a link’s target is within the “top-of-transfer directory”.
      This is not the context directory and often not the source either. Also,
      this creates broken symlinks if the target is not within the source but
      is within the top-of-transfer. See examples below.

    Equivalent to the :code:`rsync(1)` options listed for :code:`+m` plus
    :code:`--links` (copy symlinks as symlinks unless otherwise specified) and
    :code:`--safe-links` (silently skip unsafe symlinks).

  :code:`+u`
    Like :code:`+l`, but *replaces* with their target “unsafe” symlinks whose
    target is outside the top-of-transfer directory, and thus *can copy data
    outside the context directory into the image*. Preserves:

    * Metadata.

    * Directory structure.

    * Symlinks, if a link’s target is within the “top-of-transfer directory”.
      This is not the context directory and often not the source either. Also,
      this creates broken symlinks if the target is not within the source but
      is within the top-of-transfer. See examples below.

    Equivalent to the :code:`rsync(1)` options listed for :code:`+m` plus
    :code:`--links` (copy symlinks as symlinks unless otherwise specified) and
    :code:`--copy-unsafe-links` (copy the target of unsafe symlinks).

  :code:`+z`
    No default arguments. Directories will not be descended, no metadata will
    be preserved, and both hard and symbolic links will be ignored, except as
    otherwise specified by :code:`rsync(1)` options starting with a hyphen.
    (Note that :code:`-a`/:code:`--archive` is discouraged because it omits
    some metadata and handles symlinks inappropriately for containers.)

.. note::

   :code:`rsync(1)` supports a configuration file :code:`~/.popt` that alters
   its command line processing. Currently, this configuration is respected for
   :code:`RSYNC` arguments, but that may change without notice.

Disallowed :code:`rsync(1)` features
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A small number of :code:`rsync(1)` features are actively disallowed:

  1. :code:`rsync:` and :code:`ssh:` transports are an error. Charliecloud
     needs access to the entire input to compute cache hit or miss, and these
     transports make that impossible. It is possible these will become
     available in the future (please let us know if that is your use case!).
     For now, the workaround is to install :code:`rsync(1)` in the image and
     use it in a :code:`RUN` instruction, though only the instruction text
     will be considered for the cache.

  2. Option arguments must be delimited with :code:`=` (equals). For example,
     to set the block size to 4 MiB, you must say :code:`--block-size=4M` or
     :code:`-B=4M`. :code:`-B4M` will be interpreted as the three arguments
     :code:`-B`, :code:`-4`, and :code:`-M`; :code:`--block-size 4M` will be
     interpreted as :code:`--block-size` with no argument and a copy source
     named :code:`4M`. This is so Charliecloud can process :code:`rsync(1)`
     options without knowing which ones take an argument.

  3. Invalid :code:`rsync(1)` options:

     :code:`--daemon`
       Running :code:`rsync(1)` in daemon mode does not make sense for
       container build.

     :code:`-n`, :code:`--dry-run`
       This makes the copy a no-op, and Charliecloud may want to use it
       internally in the future.

     :code:`--remove-source-files`
       This would let the instruction alter the context directory.

Note that there are likely other flags that don’t make sense and/or cause
undesirable behavior. We have not characterized this problem.

Build cache
~~~~~~~~~~~

The instruction is a cache hit if the metadata of all source files is
unchanged (specifically: filename, file type and permissions, xattrs, size,
and last modified time). Unlike Docker, Charliecloud does not use file
contents. This has two implications. First, it is possible to fool the cache
by manually restoring the last-modified time. Second, :code:`RSYNC` is
I/O-intensive even when it hits, because it must :code:`stat(2)` every source
file before checking the cache. However, this is still less I/O than reading
the file content too.

Notably, Charliecloud’s cache ignores :code:`rsync(1)`’s own internal notion
of whether anything would be transferred (e.g., :code:`rsync -ni`). This may
change in the future.

Examples and tutorial
~~~~~~~~~~~~~~~~~~~~~

All of these examples use the same input, whose content will be introduced
gradually, using edited output of :code:`ls -oghR` (which is like :code:`ls
-lhR` but omits user and group). Examples assume a umask of :code:`0007`. The
Dockerfile instructions listed also assume a preceding:

.. code-block:: docker

   FROM alpine:3.17
   RUN mkdir /dst

i.e., a simple base image containing a top-level directory :code:`dst`.

Many additional examples are available in the source code in the file
:code:`test/build/50_rsync.bats`.

We begin by copying regular files. The context directory :code:`ctx` contains,
in part, two directories containing one regular file each. Note that one of
these files (:code:`file-basic1`) and one of the directories (:code:`basic1`)
have strange permissions.

::

   ./ctx:
   drwx---r-x 2  60 Oct 11 13:20 basic1
   drwxrwx--- 2  60 Oct 11 13:20 basic2

   ./ctx/basic1:
   -rw----r-- 1 12 Oct 11 13:20 file-basic1

   ./ctx/basic2:
   -rw-rw---- 1 12 Oct 11 13:20 file-basic2

The simplest form of :code:`RSYNC` is to copy a single file into a specified
directory:

.. code-block:: docker

   RSYNC /basic1/file-basic1 /dst

resulting in::

   $ ls -oghR dst
   dst:
   -rw----r-- 1 12 Oct 11 13:26 file-basic1

Note that :code:`file-basic1`’s metadata — here its odd permissions — are
preserved. :code:`1` is the number of hard links to the file, and :code:`12`
is the file size.

One can also rename the destination by specifying a new file name, and with
:code:`+z`, not copy metadata (from here on the :code:`ls` command is omitted
for brevity):

.. code-block:: docker

   RSYNC +z /basic1/file-basic1 /dst/file-basic1_nom

::

   dst:
   -rw------- 1 12 Sep 21 15:51 file-basic1_nom

A trailing slash on the destination creates a new directory and places the
source file within:

.. code-block:: docker

   RSYNC /basic1/file-basic1 /dst/new/

::

   dst:
   drwxrwx--- 1 22 Oct 11 13:26 new

   dst/new:
   -rw----r-- 1 12 Oct 11 13:26 file-basic1

With multiple source files, the destination trailing slash is optional:

.. code-block:: docker

   RSYNC /basic1/file-basic1 /basic2/file-basic2 /dst/newB

::

   dst:
   drwxrwx--- 1 44 Oct 11 13:26 newB

   dst/newB:
   -rw----r-- 1 12 Oct 11 13:26 file-basic1
   -rw-rw---- 1 12 Oct 11 13:26 file-basic2

For directory sources, the presence or absence of a trailing slash is highly
significant. Without one, the directory itself is placed in the destination
(recall that this would rename a source *file*):

.. code-block:: docker

   RSYNC /basic1 /dst/basic1_new

::

   dst:
   drwxrwx--- 1 12 Oct 11 13:28 basic1_new

   dst/basic1_new:
   drwx---r-x 1 22 Oct 11 13:28 basic1

   dst/basic1_new/basic1:
   -rw----r-- 1 12 Oct 11 13:28 file-basic1

A source trailing slash means copy the *contents of* a directory rather than
the directory itself. Importantly, however, the directory’s metadata is copied
to the destination directory.

.. code-block:: docker

   RSYNC /basic1/ /dst/basic1_renamed

::

   dst:
   drwx---r-x 1 22 Oct 11 13:28 basic1_renamed

   dst/basic1_renamed:
   -rw----r-- 1 12 Oct 11 13:28 file-basic1

One gotcha is that :code:`RSYNC +z` is a no-op if the source is a directory:

.. code-block:: docker

   RSYNC +z /basic1 /dst/basic1_newC

::

   dst:

At least :code:`-r` is needed with :code:`+z` in this case:

.. code-block:: docker

   RSYNC +z -r /basic1/ /dst/basic1_newD

::

   dst:
   drwx------ 1 22 Oct 11 13:28 basic1_newD

   dst/basic1_newD:
   -rw------- 1 12 Oct 11 13:28 file-basic1

Multiple source directories can be specified, including with wildcards. This
example also illustrates that copies files are by default merged with content
already existing in the image.

.. code-block:: docker

   RUN mkdir /dst/dstC && echo file-dstC > /dst/dstC/file-dstC
   RSYNC /basic* /dst/dstC

::

   dst:
   drwxrwx--- 1 42 Oct 11 13:33 dstC

   dst/dstC:
   drwx---r-x 1 22 Oct 11 13:33 basic1
   drwxrwx--- 1 22 Oct 11 13:33 basic2
   -rw-rw---- 1 10 Oct 11 13:33 file-dstC

   dst/dstC/basic1:
   -rw----r-- 1 12 Oct 11 13:33 file-basic1

   dst/dstC/basic2:
   -rw-rw---- 1 12 Oct 11 13:33 file-basic2

Trailing slashes can be specified independently for each source:

.. code-block:: docker

   RUN mkdir /dst/dstF && echo file-dstF > /dst/dstF/file-dstF
   RSYNC /basic1 /basic2/ /dst/dstF

::

   dst:
   drwxrwx--- 1 52 Oct 11 13:33 dstF

   dst/dstF:
   drwx---r-x 1 22 Oct 11 13:33 basic1
   -rw-rw---- 1 12 Oct 11 13:33 file-basic2
   -rw-rw---- 1 10 Oct 11 13:33 file-dstF

   dst/dstF/basic1:
   -rw----r-- 1 12 Oct 11 13:33 file-basic1

Bare :code:`/` (i.e., the entire context directory) is considered to have a
trailing slash:

.. code-block:: docker

   RSYNC / /dst

::

   dst:
   drwx---r-x 1  22 Oct 11 13:33 basic1
   drwxrwx--- 1  22 Oct 11 13:33 basic2

   dst/basic1:
   -rw----r-- 1 12 Oct 11 13:33 file-basic1

   dst/basic2:
   -rw-rw---- 1 12 Oct 11 13:33 file-basic2

To *replace* (rather than merge with) existing content, use :code:`--delete`.
Note also that wildcards can be combined with trailing slashes and that the
directory gets the metadata of the *first* slashed directory.

.. code-block:: docker

   RUN mkdir /dst/dstG && echo file-dstG > /dst/dstG/file-dstG
   RSYNC --delete /basic*/ /dst/dstG

::

   dst:
   drwx---r-x 1 44 Oct 11 14:00 dstG

   dst/dstG:
   -rw----r-- 1 12 Oct 11 14:00 file-basic1
   -rw-rw---- 1 12 Oct 11 14:00 file-basic2

Symbolic links in the source(s) add significant complexity. Like
:code:`rsync(1)`, :code:`RSYNC` can do one of three things with a given
symlink:

1. Ignore it, silently or with a warning.

2. Preserve it: copy as a symlink, with the same target.

3. Dereference it: copy the target instead.

These actions are selected independently for *safe symlinks* and *unsafe
symlinks*. Safe symlinks are those which point to a target within the *top of
transfer*, which is the deepest directory in the source path with a trailing
slash. For example, :code:`/foo/bar`’s top-of-transfer is :code:`/foo`
(regardless of whether :code:`bar` is a directory or file), while
:code:`/foo/bar/`’s top-of-transfer is :code:`/foo/bar`.

For the symlink examples, the context contains two sub-directories with a
variety of symlinks, as well as a sibling file and directory outside the
context. All of these links are valid on the host. In this listing, the
absolute path to the parent of the context directory is replaced with
:code:`/...`.

::

   .:
   drwxrwx--- 9 200 Oct 11 14:00 ctx
   drwxrwx--- 2  60 Oct 11 14:00 dir-out
   -rw-rw---- 1   9 Oct 11 14:00 file-out

   ./ctx:
   drwxrwx--- 3 320 Oct 11 14:00 sym1

   ./ctx/sym1:
   lrwxrwxrwx 1 13 Oct 11 14:00 dir-out_rel -> ../../dir-out
   drwxrwx--- 2 60 Oct 11 14:00 dir-sym1
   lrwxrwxrwx 1  8 Oct 11 14:00 dir-sym1_direct -> dir-sym1
   lrwxrwxrwx 1 10 Oct 11 14:00 dir-top_rel -> ../dir-top
   lrwxrwxrwx 1 47 Oct 11 14:00 file-out_abs -> /.../file-out
   lrwxrwxrwx 1 14 Oct 11 14:00 file-out_rel -> ../../file-out
   -rw-rw---- 1 10 Oct 11 14:00 file-sym1
   lrwxrwxrwx 1 57 Oct 11 14:00 file-sym1_abs -> /.../ctx/sym1/file-sym1
   lrwxrwxrwx 1  9 Oct 11 14:00 file-sym1_direct -> file-sym1
   lrwxrwxrwx 1 17 Oct 11 14:00 file-sym1_upover -> ../sym1/file-sym1
   lrwxrwxrwx 1 51 Oct 11 14:00 file-top_abs -> /.../ctx/file-top
   lrwxrwxrwx 1 11 Oct 11 14:00 file-top_rel -> ../file-top

   ./ctx/sym1/dir-sym1:
   -rw-rw---- 1 14 Oct 11 14:00 dir-sym1.file

   ./dir-out:
   -rw-rw---- 1 13 Oct 11 14:00 dir-out.file

By default, safe symlinks are preserved while unsafe symlinks are silently
ignored:

.. code-block:: docker

   RSYNC /sym1 /dst

::

   dst:
   drwxrwx--- 1 206 Oct 11 17:10 sym1

   dst/sym1:
   drwxrwx--- 1 26 Oct 11 17:10 dir-sym1
   lrwxrwxrwx 1  8 Oct 11 17:10 dir-sym1_direct -> dir-sym1
   lrwxrwxrwx 1 10 Oct 11 17:10 dir-top_rel -> ../dir-top
   -rw-rw---- 1 10 Oct 11 17:10 file-sym1
   lrwxrwxrwx 1  9 Oct 11 17:10 file-sym1_direct -> file-sym1
   lrwxrwxrwx 1 17 Oct 11 17:10 file-sym1_upover -> ../sym1/file-sym1
   lrwxrwxrwx 1 17 Oct 11 17:10 file-sym2_upover -> ../sym2/file-sym2
   lrwxrwxrwx 1 11 Oct 11 17:10 file-top_rel -> ../file-top

   dst/sym1/dir-sym1:
   -rw-rw---- 1 14 Oct 11 17:10 dir-sym1.file

The source files have four rough fates:

1. Regular files and directories (:code:`file-sym1` and :code:`dir-sym1`).
   These are copied into the image unchanged, including metadata.

2. Safe symlinks, now broken. This is one of the gotchas of :code:`RSYNC`’s
   top-of-transfer directory (here host path :code:`./ctx`, image path
   :code:`/`) differing from the source directory (:code:`./ctx/sym1`,
   :code:`/sym1`), because the latter lacks a trailing slash.
   :code:`dir-top_rel`, :code:`file-sym2_upover`, and :code:`file-top_rel` all
   ascend only as high as :code:`./ctx` (host path, :code:`/` image) before
   re-descending. This is within the top-of-transfer, so the symlinks are safe
   and thus copied unchanged, but their targets were not included in the copy.

3. Safe symlinks, still valid.

   1. :code:`dir-sym1_direct` and :code:`file-sym1_direct` point directly to
      files in the same directory.

   2. :code:`dir-sym1_upover` and :code:`file-sym1_upover` point to files in
      the same directory, but by first ascending into their parent — within
      the top-of-transfer, so they are safe — and then re-descending. If
      :code:`sym1` were renamed during the copy, these links would break.

4. Unsafe symlinks, which are ignored by the copy and do not appear in the
   image.

   1. Absolute symlinks are always unsafe (:code:`*_abs`).

   2. :code:`dir-out_rel` and :code:`file-out_rel` are relative symlinks that
      ascend above the top-of-transfer, in this case to targets outside the
      context, and are thus unsafe.

The top-of-transfer can be changed to :code:`sym1` with a trailing slash. This
also adds :code:`sym1` to the destination so the resulting directory structure
is the same.

.. code-block:: docker

   RSYNC /sym1/ /dst/sym1

::

   dst:
   drwxrwx--- 1 96 Oct 11 17:10 sym1

   dst/sym1:
   drwxrwx--- 1 26 Oct 11 17:10 dir-sym1
   lrwxrwxrwx 1  8 Oct 11 17:10 dir-sym1_direct -> dir-sym1
   -rw-rw---- 1 10 Oct 11 17:10 file-sym1
   lrwxrwxrwx 1  9 Oct 11 17:10 file-sym1_direct -> file-sym1

   dst/sym1/dir-sym1:
   -rw-rw---- 1 14 Oct 11 17:10 dir-sym1.file

:code:`*_upover` and :code:`*-out_rel` are now unsafe and replaced with their
targets.

Another common use case is to follow unsafe symlinks and copy their targets in
place of the links. This is accomplished with :code:`+u`:

.. code-block:: docker

   RSYNC +u /sym1/ /dst/sym1

::

   dst:
   drwxrwx--- 1 352 Oct 11 17:10 sym1

   dst/sym1:
   drwxrwx--- 1 24 Oct 11 17:10 dir-out_rel
   drwxrwx--- 1 26 Oct 11 17:10 dir-sym1
   lrwxrwxrwx 1  8 Oct 11 17:10 dir-sym1_direct -> dir-sym1
   drwxrwx--- 1 24 Oct 11 17:10 dir-top_rel
   -rw-rw---- 1  9 Oct 11 17:10 file-out_abs
   -rw-rw---- 1  9 Oct 11 17:10 file-out_rel
   -rw-rw---- 1 10 Oct 11 17:10 file-sym1
   -rw-rw---- 1 10 Oct 11 17:10 file-sym1_abs
   lrwxrwxrwx 1  9 Oct 11 17:10 file-sym1_direct -> file-sym1
   -rw-rw---- 1 10 Oct 11 17:10 file-sym1_upover
   -rw-rw---- 1 10 Oct 11 17:10 file-sym2_abs
   -rw-rw---- 1 10 Oct 11 17:10 file-sym2_upover
   -rw-rw---- 1  9 Oct 11 17:10 file-top_abs
   -rw-rw---- 1  9 Oct 11 17:10 file-top_rel

   dst/sym1/dir-out_rel:
   -rw-rw---- 1 13 Oct 11 17:10 dir-out.file

   dst/sym1/dir-sym1:
   -rw-rw---- 1 14 Oct 11 17:10 dir-sym1.file

   dst/sym1/dir-top_rel:
   -rw-rw---- 1 13 Oct 11 17:10 dir-top.file

Now all the unsafe symlinks noted above are present in the image, but they
have changed to the normal files and directories pointed to.

.. warning::

   This feature lets you copy files outside the context into the image, unlike
   other container builders where :code:`COPY` can never access anything
   outside the context.

The sources themselves, if symlinks, do not get special treatment:

.. code-block:: docker

   RSYNC /sym1/file-sym1_direct /sym1/file-sym1_upover /dst

::

   dst:
   lrwxrwxrwx 1 9 Oct 11 17:10 file-sym1_direct -> file-sym1

Note that :code:`file-sym1_upover` does not appear in the image, despite being
named explicitly in the instruction, because it is an unsafe symlink.

If the *destination* is a symlink to a file, and the source is a file, the
link is replaced and the target is unchanged. (If the source is a directory,
that is an error.)

.. code-block:: docker

   RUN touch /dst/file-dst && ln -s file-dst /dst/file-dst_direct
   RSYNC /file-top /dst/file-dst_direct

::

   dst:
   -rw-rw---- 1 0 Oct 11 17:42 file-dst
   -rw-rw---- 1 9 Oct 11 17:42 file-dst_direct

If the destination is a symlink to a directory, the link is followed:

.. code-block:: docker

    RUN mkdir /dst/dir-dst && ln -s dir-dst /dst/dir-dst_direct
    RSYNC /file-top /dst/dir-dst_direct

::

   dst:
   drwxrwx--- 1 16 Oct 11 17:50 dir-dst
   lrwxrwxrwx 1  7 Oct 11 17:50 dir-dst_direct -> dir-dst

   dst/dir-dst:
   -rw-rw---- 1 9 Oct 11 17:50 file-top

Examples
--------

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
installing into the image::

   $ ch-image build --bind /opt/bigvendor:/opt .
   $ cat Dockerfile
   FROM centos:7

   RUN /opt/bin/cc hello.c
   #COPY /opt/lib/*.so /usr/local/lib   # fail: COPY doesn’t bind mount
   RUN cp /opt/lib/*.so /usr/local/lib  # possible workaround
   RUN ldconfig

:code:`build-cache`
===================

::

   $ ch-image [...] build-cache [...]

Print basic information about the cache. If :code:`-v` is given, also print
some Git statistics and the Git repository configuration.

If any of the following options are given, do the corresponding operation
before printing. Multiple options can be given, in which case they happen in
this order.

  :code:`--dot`
    Create a DOT export of the tree named :code:`./build-cache.dot` and a PDF
    rendering :code:`./build-cache.pdf`. Requires :code:`graphviz` and
    :code:`git2dot`.

  :code:`--gc`
    Run Git garbage collection on the cache, including full de-duplication of
    similar files. This will immediately remove all cache entries not
    currently reachable from a named branch (which is likely to cause
    corruption if the build cache is being accessed concurrently by another
    process). The operation can take a long time on large caches.

  :code:`--reset`
    Clear and re-initialize the build cache.

  :code:`--tree`
    Print a text tree of the cache using Git’s :code:`git log --graph`
    feature. If :code:`-v` is also given, the tree has more detail.

:code:`delete`
==============

::

   $ ch-image [...] delete IMAGE_GLOB [IMAGE_GLOB ... ]

Delete the image(s) described by each :code:`IMAGE_GLOB` from the storage
directory (including all build stages).

:code:`IMAGE_GLOB` can be either a plain image reference or an image reference
with glob characters to match multiple images. For example, :code:`ch-image
delete 'foo*'` will delete all images whose names start with :code:`foo`.
Multiple images and/or globs can also be given in a single command line.

Importantly, this sub-command *does not* also remove the image from the build
cache. Therefore, it can be used to reduce the size of the storage directory,
trading off the time needed to retrieve an image from cache.

.. warning::

   Glob characters must be quoted or otherwise protected from the shell, which
   also desires to interpret them and will do so incorrectly.

:code:`gestalt`
===============

::

   $ ch-image [...] gestalt [SELECTOR]

Provide information about the `configuration and available features
<https://apple.fandom.com/wiki/Gestalt>`_ of :code:`ch-image`. End users
generally will not need this; it is intended for testing and debugging.

:code:`SELECTOR` is one of:

   * :code:`bucache`. Exit successfully if the build cache is available,
     unsuccessfully with an error message otherwise. With :code:`-v`, also
     print version information about dependencies.

   * :code:`bucache-dot`. Exit successfully if build cache DOT trees can be
     written, unsuccessfully with an error message otherwise. With :code:`-v`,
     also print version information about dependencies.

   * :code:`python-path`. Print the path to the Python interpreter in use and
     exit successfully.

   * :code:`storage-path`. Print the storage directory path and exit
     successfully.


:code:`list`
============

Print information about images. If no argument given, list the images in
builder storage.

Synopsis
--------

::

   $ ch-image [...] list [-l] [IMAGE_REF]

Description
-----------

Optional argument:

  :code:`-l`, :code:`--long`
    Use long format (name, last change timestamp) when listing images.

  :code:`-u`, :code:`--undeletable`
    List images that can be undeleted. Can also be spelled :code:`--undeleteable`.

  :code:`IMAGE_REF`
    Print details of what’s known about :code:`IMAGE_REF`, both locally and in
    the remote registry, if any.

Examples
--------

List images in builder storage::

   $ ch-image list
   alpine:3.17 (amd64)
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
   archs available:     386       bae2738ed83
                        amd64     98285d32477
                        arm/v7    97247fd4822
                        arm64/v8  122a0342878

For remotely available images like Debian Buster, the associated digest is
listed beside each available architecture. Importantly, this feature does
*not* provide the hash of the local image, which is only calculated on push.


:code:`import`
==============

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

.. warning::

   Descendant images (i.e., :code:`FROM` the imported :code:`IMAGE_REF`) are
   linked using :code:`IMAGE_REF` only. If a new image is imported under a new
   :code:`IMAGE_REF`, all instructions descending from that :code:`IMAGE_REF`
   will still hit, even if the new image is different.


:code:`modify`
==============

Interactively edit the specified image.

Synopsis
--------

::

   $ ch-image [...] modify [...] TARGET

Description
-----------

This subcommand starts a shell on the image named :code:`TARGET`, in order to
edit the image interactively. It is similar to a :code:`RUN` instruction that
starts an interactive shell. By default, ask the user whether to save changes
when the shell exits.

Options:

  :code:`-m MSG`
    Use :code:`MSG` to identify the edits to the build cache. That is, if you
    run this command twice with the same :code:`TARGET`, the same :code:`-o
    DEST`, and the same :code:`MSG`, the second session will overwrite the
    first. (Without :code:`-o`, the second session will build atop the first.)
    By default, every interactive session is considered different from every
    other, as if a random :code:`MSG` were entered.

  :code:`-o`, :code:`--out DEST`
    Save the results in image named :code:`DEST`, leaving :code:`TARGET`
    unchanged.

  :code:`-s`, :code:`--shell SHELL`
    Start :code:`SHELL` instead of :code:`/bin/sh`.

  :code:`-y`, :code:`--yes`
    Do not prompt the user to save. Instead, save if the shell exits
    successfully, and roll back if it exits unsuccessfully, e.g. by executing
    :code:`exit 1`.

.. warning::

   This subcommand is rarely needed. Non-interactive build using a Dockerfile
   is almost always better, because it preserves the sequence of operations
   that created an image. Only use this subcommand if you really know what you
   are doing.

Examples
--------

To edit the image :code:`foo`, adding :code:`/opt/lib` to the default shared
library search path, producing image :code:`bar` as the result::

   $ ch-image modify -o bar foo
   [...]
   > emacs /etc/ld.so.conf
   [... append line “/opt/lib” to the file ...]
   > ldconfig
   > exit
   Save changes ([y]/n)? y
   committing ...
   [...]

Equivalently, and almost certainly preferred::

   $ cat Dockerfile
   FROM foo
   RUN echo /opt/lib >> /etc/ld.so.conf
   RUN ldconfig
   $ ch-image build -t bar -f Dockerfile .


:code:`pull`
============

Pull the image described by the image reference :code:`IMAGE_REF` from a
repository to the local filesystem.

Synopsis
--------

::

   $ ch-image [...] pull [...] IMAGE_REF [DEST_REF]

See the FAQ for the gory details on specifying image references.

Description
-----------

Destination:

  :code:`DEST_REF`
    If specified, use this as the destination image reference, rather than
    :code:`IMAGE_REF`. This lets you pull an image with a complicated
    reference while storing it locally with a simpler one.

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
    image if they don’t exist, but no other action is taken.

Note that some images (e.g., those with a "version 1 manifest") do not contain
metadata. A warning is printed in this case.

Examples
--------

Download the Debian Buster image matching the host’s architecture and place it
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


:code:`push`
============

Push the image described by the image reference :code:`IMAGE_REF` from the
local filesystem to a repository.

Synopsis
--------

::

   $ ch-image [...] push [--image DIR] IMAGE_REF [DEST_REF]

See the FAQ for the gory details on specifying image references.

Description
-----------

Destination:

  :code:`DEST_REF`
    If specified, use this as the destination image reference, rather than
    :code:`IMAGE_REF`. This lets you push to a repository without permanently
    adding a tag to the image.

Options:

  :code:`--image DIR`
    Use the unpacked image located at :code:`DIR` rather than an image in the
    storage directory named :code:`IMAGE_REF`.

Because Charliecloud is fully unprivileged, the owner and group of files in
its images are not meaningful in the broader ecosystem. Thus, when pushed,
everything in the image is flattened to user:group :code:`root:root`. Also,
setuid/setgid bits are removed, to avoid surprises if the image is pulled by a
privileged container implementation.

Examples
--------

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

Same, except use local image :code:`alpine:3.17`. In this form, the local image
name does not have to match the destination reference.

::

   $ ch-image push alpine:3.17 example.com:5000/foo/bar:latest
   pushing image:   alpine:3.17
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
in the remote registry, so we don’t upload it again.)

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


:code:`reset`
=============

::

   $ ch-image [...] reset

Delete all images and cache from ch-image builder storage.


:code:`undelete`
================

::

   $ ch-image [...] undelete IMAGE_REF

If :code:`IMAGE_REF` has been deleted but is in the build cache, recover it
from the cache. Only available when the cache is enabled, and will not
overwrite :code:`IMAGE_REF` if it exists.


Environment variables
=====================

:code:`CH_IMAGE_USERNAME`, :code:`CH_IMAGE_PASSWORD`
  Username and password for registry authentication. **See important caveats
  in section "Authentication" above.**

.. include:: py_env.rst


.. include:: ./bugs.rst
.. include:: ./see_also.rst

..  LocalWords:  tmpfs'es bigvendor AUTH auth bucache buc bigfile df rfc bae
..  LocalWords:  dlcache graphviz packfile packfiles bigFileThreshold fd Tpdf
..  LocalWords:  pstats gprof chofile cffd cacdb ARGs NSYNC dst imgroot popt
..  LocalWords:  globbed ni AHSXpr drwxrwx ctx sym nom newB newC newD dstC
..  LocalWords:  dstB dstF dstG upover drwx kexec
