:code:`ch-run`
++++++++++++++

.. only:: not man

   Run a command in a Charliecloud container.


Synopsis
========

::

  $ ch-run [OPTION...] IMAGE -- COMMAND [ARG...]


Description
===========

Run command :code:`COMMAND` in a fully unprivileged Charliecloud container using
the image specified by :code:`IMAGE`, which can be: (1) a path to a directory,
(2) the name of an image in :code:`ch-image` storage (e.g.
:code:`example.com:5050/foo`) or, if the proper support is enabled, a SquashFS
archive. :code:`ch-run` does not use any setuid or setcap helpers, even for
mounting SquashFS images with FUSE.

  :code:`-b`, :code:`--bind=SRC[:DST]`
    Bind-mount :code:`SRC` at guest :code:`DST`. The default destination if
    not specified is to use the same path as the host; i.e., the default is
    :code:`--bind=SRC:SRC`. Can be repeated.

    With a read-only image (the default), :code:`DST` must exist. However, if
    :code:`--write` or :code:`--write-fake` are given, :code:`DST` will be
    created as an empty directory (possibly with the tmpfs overmount trick
    described in :ref:`faq_mkdir-ro`). In this case, :code:`DST` must be
    entirely within the image itself, i.e., :code:`DST` cannot enter a
    previous bind mount. For example, :code:`--bind /foo:/tmp/foo` will fail
    because :code:`/tmp` is shared with the host via bind-mount (unless
    :code:`$TMPDIR` is set to something else or :code:`--private-tmp` is
    given).

    Most images have ten directories :code:`/mnt/[0-9]` already available as
    mount points.

    Symlinks in :code:`DST` are followed, and absolute links can have
    surprising behavior. Bind-mounting happens after namespace setup but
    before pivoting into the container image, so absolute links use the host
    root. For example, suppose the image has a symlink :code:`/foo -> /mnt`.
    Then, :code:`--bind=/bar:/foo` will bind-mount on the *host’s*
    :code:`/mnt`, which is inaccessible on the host because namespaces are
    already set up and *also* inaccessible in the container because of the
    subsequent pivot into the image. Currently, this problem is only detected
    when :code:`DST` needs to be created: :code:`ch-run` will refuse to follow
    absolute symlinks in this case, to avoid directory creation surprises.

  :code:`-c`, :code:`--cd=DIR`
    Initial working directory in container.

  :code:`--cdi-dirs=PATHS`
    Colon-separated list of directories to search for CDI JSON specifications.
    Default: :code:`CH_RUN_CDI_DIRS` if set, otherwise
    :code:`/etc/cdi:/var/run/cdi`.

  :code:`--color[=WHEN]`
    Color logging output by log level when :code:`WHEN`:

       * By default, or if :code:`WHEN` is :code:`auto`, :code:`tty`,
         :code:`if-tty`: use color if standard error is a TTY; otherwise,
         don’t use color.

       * If :code:`WHEN` is :code:`yes`, :code:`always`, or :code:`force`; or
         if :code:`--color` is specified without an argument: always use
         color.

       * If :code:`WHEN` is :code:`no`, :code:`never`, or :code:`none`: never
         use color.

    This uses ANSI color codes without checking any terminal databases, which
    should work on all modern terminals.

  :code:`-d`, :code:`--devices`
    Inject all CDI devices for which a specification is found. Implies
    :code:`--write-fake`.

  :code:`--device=DEV`
    Inject CDI device :code:`DEV`, either (1) a filename, if it starts with a
    slash (:code:`/`) or dot (:code:`.`), e.g. :code:`/etc/cdi/nvidia.json`,
    or (2) a CDI selector for a list of devices in a CDI specification file,
    e.g. :code:`nvidia.com/gpu`. Specific devices may not be selected, e.g.
    :code:`nvidia.com/gpu=1:0` is invalid (see below for why). Implies
    :code:`--write-fake`. Can be repeated.

  :code:`--env-no-expand`
    Don’t expand variables when using :code:`--set-env`.

  :code:`--feature=FEAT`
    If feature :code:`FEAT` is enabled, exit successfully (zero); otherwise,
    exit unsuccessfully (non-zero). Note this just communicates the results of
    :code:`configure` rather than testing the feature. Valid values of
    :code:`FEAT` are:

       * :code:`extglob`: extended globs in :code:`--unset-env`
       * :code:`seccomp`: :code:`--seccomp` available
       * :code:`squash`: internal SquashFUSE image mounts
       * :code:`overlayfs`: unprivileged overlayfs support
       * :code:`tmpfs-xattrs`: :code:`user` xattrs on tmpfs

  :code:`-g`, :code:`--gid=GID`
    Run as group :code:`GID` within container.

  :code:`--home`
    Bind-mount your host home directory (i.e., :code:`$HOME`) at guest
    :code:`/home/$USER`, hiding any existing image content at that path.
    Implies :code:`--write-fake` so the mount point can be created if needed.

  :code:`-j`, :code:`--join`
    Use the same container (namespaces) as peer :code:`ch-run` invocations.

  :code:`--join-pid=PID`
    Join the namespaces of an existing process.

  :code:`--join-ct=N`
    Number of :code:`ch-run` peers (implies :code:`--join`; default: see
    below).

  :code:`--join-tag=TAG`
    Label for :code:`ch-run` peer group (implies :code:`--join`; default: see
    below).

  :code:`-m`, :code:`--mount=DIR`
    Use :code:`DIR` for the SquashFS mount point, which must already exist. If
    not specified, the default is :code:`/var/tmp/$USER.ch/mnt`, which *will*
    be created if needed.

  :code:`--no-passwd`
    By default, temporary :code:`/etc/passwd` and :code:`/etc/group` files are
    created according to the UID and GID maps for the container and
    bind-mounted into it. If this is specified, no such temporary files are
    created and the image’s files are exposed.

  :code:`-q`, :code:`--quiet`
    Be quieter; can be repeated. Incompatible with :code:`-v`. See the
    :ref:`faq_verbosity` for details.

  :code:`-s`, :code:`--storage DIR`
    Set the storage directory. Equivalent to the same option for
    :code:`ch-image(1)`.

  :code:`--seccomp`
    Using seccomp, intercept some system calls that would fail due to lack of
    privilege, do nothing, and return fake success to the calling program.
    This is intended for use by :code:`ch-image(1)` when building images; see
    that man page for a detailed discussion.

  :code:`--set-env`, :code:`--set-env=FILE`, :code:`--set-env=VAR=VALUE`
    Set environment variables with newline-separated file
    (:code:`/ch/environment` within the image if not specified) or on the
    command line. See below for details.

  :code:`--set-env0`, :code:`--set-env0=FILE`, :code:`--set-env0=VAR=VALUE`
    Like :code:`--set-env`, but file is null-byte separated.

  :code:`-t`, :code:`--private-tmp`
    By default, the host’s :code:`/tmp` (or :code:`$TMPDIR` if set) is
    bind-mounted at container :code:`/tmp`. If this is specified, a new
    :code:`tmpfs` is mounted on the container’s :code:`/tmp` instead.

  :code:`-u`, :code:`--uid=UID`
    Run as user :code:`UID` within container.

  :code:`--unsafe`
    Enable various unsafe behavior. For internal use only. Seriously, stay
    away from this option.

  :code:`--unset-env=GLOB`
    Unset environment variables whose names match :code:`GLOB`.

  :code:`-v`, :code:`--verbose`
    Print extra chatter; can be repeated. See the :ref:`FAQ entry on verbosity
    <faq_verbosity>` for details.

  :code:`-w`, :code:`--write`
    Mount image read-write. By default, the image is mounted read-only. *This
    option should be avoided for most use cases,* because (1) changing images
    live (as opposed to prescriptively with a Dockerfile) destroys their
    provenance and (2) SquashFS images, which is the best-practice format on
    parallel filesystems, must be read-only. It is better to use
    :code:`--write-fake` (for disposable data) or bind-mount host directories
    (for retained data).

  :code:`-W`, :code:`--write-fake[=SIZE]`
    Overlay a writeable tmpfs on top of the image. This makes the image
    *appear* read-write, but it actually remains read-only and unchanged. All
    data “written” to the image are discarded when the container exits.

    The size of the writeable filesystem :code:`SIZE` is any size
    specification acceptable to :code:`tmpfs`, e.g. :code:`4m` for 4MiB or
    :code:`50%` for half of physical memory. If this option is specified
    without :code:`SIZE`, the default is :code:`12%`. Note (1) this limit is a
    maximum — only actually stored files consume virtual memory — and
    (2) :code:`SIZE` larger than memory can be requested without error (the
    failure happens later if the actual contents become too large).

    This requires kernel support and there are some caveats. See section
    “:ref:`ch-run_overlay`” below for details.

  :code:`-?`, :code:`--help`
    Print help and exit.

  :code:`--usage`
    Print a short usage message and exit.

  :code:`-V`, :code:`--version`
    Print version and exit.

**Note:** Because :code:`ch-run` is fully unprivileged, it is not possible to
change UIDs and GIDs within the container (the relevant system calls fail). In
particular, setuid, setgid, and setcap executables do not work. As a
precaution, :code:`ch-run` calls :code:`prctl(PR_SET_NO_NEW_PRIVS, 1)` to
`disable these executables
<https://www.kernel.org/doc/Documentation/prctl/no_new_privs.txt>`_ within the
container. This does not reduce functionality but is a "belt and suspenders"
precaution to reduce the attack surface should bugs in these system calls or
elsewhere arise.


Image format
============

:code:`ch-run` supports two different image formats.

The first is a simple directory that contains a Linux filesystem tree. This
can be accomplished by:

* :code:`ch-convert` directly from :code:`ch-image` or another builder to a
  directory.

* Charliecloud’s tarball workflow: build or pull the image, :code:`ch-convert`
  it to a tarball, transfer the tarball to the target system, then
  :code:`ch-convert` the tarball to a directory.

* Manually mount a SquashFS image, e.g. with :code:`squashfuse(1)` and then
  un-mount it after run with :code:`fusermount -u`.

* Any other workflow that produces an appropriate directory tree.

The second is a SquashFS image archive mounted internally by :code:`ch-run`,
available if it’s linked with the optional :code:`libsquashfuse_ll` shared
library. :code:`ch-run` mounts the image filesystem, services all FUSE
requests, and unmounts it, all within :code:`ch-run`. See :code:`--mount`
above to set the mount point location.

Like other FUSE implementations, Charliecloud calls the :code:`fusermount3(1)`
utility to mount the SquashFS filesystem. However, **this executable does not
need to be installed setuid root**, and in fact :code:`ch-run` actively
suppresses its setuid bit if set (using :code:`prctl(2)`).

Prior versions of Charliecloud provided wrappers for the :code:`squashfuse`
and :code:`squashfuse_ll` SquashFS mount commands and :code:`fusermount -u`
unmount command. We removed these because we concluded they had minimal
value-add over the standard, unwrapped commands.

.. warning::

   Currently, Charliecloud unmounts the SquashFS filesystem when user command
   :code:`COMMAND`’s process exits. It does not monitor any of its child
   processes. Therefore, if the user command spawns child processes and then
   exits before them (e.g., some daemons), those children will have the image
   unmounted from underneath them. In this case, the workaround is to
   mount/unmount using external tools. We expect to remove this limitation in a
   future version.


Host files and directories available in container via bind mounts
=================================================================

In addition to any directories specified by the user with :code:`--bind`,
:code:`ch-run` has standard host files and directories that are bind-mounted
in as well.

The following host files and directories are bind-mounted at the same location
in the container. These give access to the host’s devices and various kernel
facilities. (Recall that Charliecloud provides minimal isolation and
containerized processes are mostly normal unprivileged processes.) They cannot
be disabled and are required; i.e., they must exist both on host and within
the image.

  * :code:`/dev`
  * :code:`/proc`
  * :code:`/sys`

Optional; bind-mounted only if path exists on both host and within the image,
without error or warning if not.

  * :code:`/etc/hosts` and :code:`/etc/resolv.conf`. Because Charliecloud
    containers share the host network namespace, they need the same hostname
    resolution configuration.

  * :code:`/etc/machine-id`. Provides a unique ID for the OS installation;
    matching the host works for most situations. Needed to support D-Bus, some
    software licensing situations, and likely other use cases. See also `issue
    #1050 <https://github.com/hpc/charliecloud/issues/1050>`_.

  * :code:`/var/lib/hugetlbfs` at guest :code:`/var/opt/cray/hugetlbfs`, and
    :code:`/var/opt/cray/alps/spool`. These support Cray MPI.

Additional bind mounts done by default but can be disabled; see the options
above.

  * :code:`$HOME` at :code:`/home/$USER` (and image :code:`/home` is hidden).
    Makes user data and init files available.

  * :code:`/tmp` (or :code:`$TMPDIR` if set) at guest :code:`/tmp`. Provides a
    temporary directory that persists between container runs and is shared
    with non-containerized application components.

  * temporary files at :code:`/etc/passwd` and :code:`/etc/group`. Usernames
    and group names need to be customized for each container run.


Multiple processes in the same container with :code:`--join`
=============================================================

By default, different :code:`ch-run` invocations use different user and mount
namespaces (i.e., different containers). While this has no impact on sharing
most resources between invocations, there are a few important exceptions.
These include:

1. :code:`ptrace(2)`, used by debuggers and related tools. One can attach a
   debugger to processes in descendant namespaces, but not sibling namespaces.
   The practical effect of this is that (without :code:`--join`), you can’t
   run a command with :code:`ch-run` and then attach to it with a debugger
   also run with :code:`ch-run`.

2. *Cross-memory attach* (CMA) is used by cooperating processes to communicate
   by simply reading and writing one another’s memory. This is also not
   permitted between sibling namespaces. This affects various MPI
   implementations that use CMA to pass messages between ranks on the same
   node, because it’s faster than traditional shared memory.

:code:`--join` is designed to address this by placing related :code:`ch-run`
commands (the “peer group”) in the same container. This is done by one of the
peers creating the namespaces with :code:`unshare(2)` and the others joining
with :code:`setns(2)`.

To do so, we need to know the number of peers and a name for the group. These
are specified by additional arguments that can (hopefully) be left at default
values in most cases:

* :code:`--join-ct` sets the number of peers. The default is the value of the
  first of the following environment variables that is defined:
  :code:`OMPI_COMM_WORLD_LOCAL_SIZE`, :code:`SLURM_STEP_TASKS_PER_NODE`,
  :code:`SLURM_CPUS_ON_NODE`.

* :code:`--join-tag` sets the tag that names the peer group. The default is
  environment variable :code:`SLURM_STEP_ID`, if defined; otherwise, the PID
  of :code:`ch-run`’s parent. Tags can be re-used for peer groups that start
  at different times, i.e., once all peer :code:`ch-run` have replaced
  themselves with the user command, the tag can be re-used.

Caveats:

* One cannot currently add peers after the fact, for example, if one decides
  to start a debugger after the fact. (This is only required for code with
  bugs and is thus an unusual use case.)

* :code:`ch-run` instances race. The winner of this race sets up the
  namespaces, and the other peers use the winner to find the namespaces to
  join. Therefore, if the user command of the winner exits, any remaining
  peers will not be able to join the namespaces, even if they are still
  active. There is currently no general way to specify which :code:`ch-run`
  should be the winner.

* If :code:`--join-ct` is too high, the winning :code:`ch-run`’s user command
  exits before all peers join, or :code:`ch-run` itself crashes, IPC resources
  such as semaphores and shared memory segments will be leaked. These appear
  as files in :code:`/dev/shm/` and can be removed with :code:`rm(1)`.

* Many of the arguments given to the race losers, such as the image path and
  :code:`--bind`, will be ignored in favor of what was given to the winner.


.. _ch-run_overlay:

Writeable overlay with :code:`--write-fake`
===========================================

If you need the image to stay read-only but appear writeable, you may be able
to use :code:`--write-fake` to overlay a writeable tmpfs atop the image. This
requires kernel support. Specifically:

1. To use the feature at all, you need unprivileged overlayfs support. This is
   available in `upstream 5.11
   <https://kernelnewbies.org/Linux_5.11#Unprivileged_Overlayfs_mounts>`_
   (February 2021), but distributions vary considerably. If you don’t have
   this, the container will fail to start with error “operation not
   permitted”.

2. For a fully functional overlay, you need a tmpfs that supports xattrs in
   the :code:`user` namespace. This is available in `upstream 6.6
   <https://kernelnewbies.org/Linux_6.6#TMPFS>`_ (October 2023). If you don’t
   have this, most things will work fine, but some operations will fail with
   “I/O error”, for example creating a directory with the same path as a
   previously deleted directory. There will also be syslog noise about xattr
   problems.

   (overlayfs can also use xattrs in the :code:`trusted` namespace, but this
   requires :code:`CAP_SYS_ADMIN` `on the host
   <https://elixir.bootlin.com/linux/v5.11/source/kernel/capability.c#L447>`_
   and thus is not helpful for unprivileged containers.)


Injecting host “devices” with Container Device Interface (CDI)
==============================================================

Overview of CDI
---------------

`Container Device Interface (CDI)
<https://github.com/cncf-tags/container-device-interface/blob/main/SPEC.md>`_
is an emerging `Cloud Native Computing Foundation (CNCF)
<https://www.cncf.io/>`_ standard to specify how “devices” are made available
to containers. Importantly, a CDI *device* is not a hardware gadget nor a
device file but rather a set of container modifications to be done before
invoking the user command. It’s intended to make devices (in the usual sense
of hardware gadgets) available inside containers but is quite flexible. A CDI
device can specify multiple device files, environment variables, mounts, and
more. Christopher Desiniotis gave a good talk at Container Plumbing Days 2024
introducing CDI (`slides
<https://static.sched.com/hosted_files/containerplumbingdays2024/e0/CDI_%20The%20Future%20of%20Specialized%20Hardware%20in%20Containers.pdf>`_,
`video <https://www.youtube.com/watch?v=MbWjw6AMMVs>`_).

CDI devices are described in JSON *specification files*, which are declarative
except they provide for arbitrary hook programs. However, Charliecloud treats
them as fully declarative by interpreting hooks as a declarative statement
rather than a program to be run (brittle, but works for now). This
declarativeness has a significant advantage over OCI hooks, because we have a
clear description of what needs to be done rather than needing to run opaque
programs as hooks.

Another advantage of CDI is that it’s largely orthogonal to OCI. While the
specifications have a strong OCI framing, this is largely an artifact of the
exposition style rather than a core notion.

Here is an example spec file:

.. literalinclude:: cdi-nvidia.json
   :language: JSON

This declares:

#. A single CDI device called :code:`nvidia.com/gpu=foo`, comprising:

   #. Two device files to be made available in the container,
      :code:`/dev/nvidia0` and :code:`/dev/dri/card0`.

   #. One symlink to create inside the container,
      :code:`/dev/by-path/pci-0000:07:00.0-card` → :code:`../card0`.

#. A set of container changes to be made once regardless of which devices are
   selected (this example has one, but real spec files have several),
   comprising:

   #. One environment variable to set, :code:`NVIDIA_VISIBLE_DEVICES`.

   #. Two device files to be made available in the container,
      :code:`/dev/nvidia-modeset` and :code:`/dev/nvidiactl`.

   #. A socket (:code:`/run/nvidia-fabricmanager/socket`), executable
      (:code:`nvidia-smi`), and shared library
      (:code:`libcuda.so.535.161.08`) to be bind-mounted into the
      container.

   #. Run the *host* :code:`ldconfig` to update the *container* linker cache,
      scanning only container directory :code:`/usr/lib/x86_64-linux-gnu`.

Charliecloud’s CDI implementation
---------------------------------

Charliecloud has some differences from other container implementations in how
this spec file is interpreted, but the results (working CDI devices) should be
the same. These are:

#. All CDI devices available to the user normally are also available in the
   container. For example, some implementations allow
   :code:`--device=nvidia.com/gpu=foo`, which puts only the GPU named
   :code:`foo` in the container, but :code:`ch-run` accepts only
   :code:`--device=nvidia.com/gpu` (and similarly in
   :code:`CH_RUN_CDI_DEFAULT`). This is because the host :code:`/dev` is
   bind-mounted into Charliecloud containers, so there is no need to deal with
   individual device files.

#. Hooks are interpreted declaratively rather than running the specified
   program. This is because we have not yet encountered any hooks that are
   both useful under Charliecloud and do a task that merits an external
   program. See below for details on individual hooks.

#. Only bind mounts are implemented, because unprivileged mount namespaces
   can’t mount much that is meaningful, and we haven’t seen any other mount
   types yet.

#. Charliecloud minimizes the number of bind mounts to avoid bloating the
   container filesystem tree. (The spec file for one of our not-that-large
   systems declares 47 mounts!) We do this by bind-mounting each filesystem
   represented in a host path once and then symlinking into it for the
   declared bind mounts.

Selecting devices
-----------------

:code:`ch-run` must do two things to make CDI devices available: (1) locate
appropriate specification files and (2) select which kinds of CDI devices to
inject. We assume further that the most common use case is to inject all
available CDI devices. The design of Charliecloud’s CDI user interface follows
from these principles.

TL;DR: The intended most common usage is simply :code:`ch-run -d` to inject
all available CDI devices, using prior configuration by users or admins.

Available spec files are those in the colon-separated list of directories in
:code:`--cdi-dirs=DIRS` if given, otherwise in :code:`CH_RUN_CDI_DIRS`,
otherwise :code:`/etc/cdi:/var/run/cdi` as required by the standard.

The option :code:`--devices` (plural) or :code:`-d` then injects all devices
found in all spec files in these directories.

Individual CDI device kinds can be selected with :code:`--device=DEV`
(singular), where :code:`DEV` is a device identifier. If it identifier starts
with slash (:code:`/`) or dot (:code:`.`), the identifier is a path to a JSON
CDI spec file, and all devices in that file are injected (e.g.,
:code:`--device=./foo.json`). Otherwise, it is a CDI device kind with no
device name(s) (e.g., :code:`--device=nvidia.com/gpu`). The option can be
repeated to inject multiple device kinds.

Importantly, both :code:`--device` and :code:`--devices` imply
:code:`--write-fake` (:code:`-W`) so the container image can be written.

Environment variables
---------------------

Injecting a CDI device may require setting environment variables, as declared
in the spec file. These environment changes are executed in the order that
that CDI command line options appear on the command line relative to other
user-specified environment options, e.g. :code:`--set-env` and
:code:`--unset-env`. See :ref:`ch-run_environment-variables` below for
details.

Hooks
------

Behavior summary
~~~~~~~~~~~~~~~~

Presently, CDI hooks fall into three categories for Charliecloud:

#. **Known hooks that we need**, with behavior emulated internally (i.e, we do
   what the hook does, adapted for Charliecloud, rather than running it).

#. **Known hooks that we don’t need**; we ignore these quietly (i.e., logged but
   a level hidden by default).

#. **Unknown hooks.** We warn about these, because they need to be either moved
   into one of the first to categories or actually run. (That is, we’re still
   figuring out what’s needed for Charliecloud here.)

The next two sections document known hooks.

.. note::

   `nVidia Container Toolkit
   <https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/index.html>`_
   CDI hooks can be spelled either `either
   <https://github.com/NVIDIA/nvidia-container-toolkit/issues/435>`_
   :code:`nvidia-ctk hook` (two words) or :code:`nvidia-ctk-hook` (one word).
   We treat the two spellings the same.

Emulated hooks
~~~~~~~~~~~~~~

#. :code:`nvidia-ctk-hook update-ldcache` . This updates the container’s
   linker cache (i.e., :code:`/etc/ld.so.cache`), `notably using
   <https://github.com/cncf-tags/container-device-interface/issues/203#issuecomment-2117628618>`_
   the *host’s* :code:`ldconfig`. For now at least, we instead use the
   *container’s* :code:`ldconfig`, the reasoning being that (1) the
   container’s linker updating its own cache is lower-risk compatibility wise
   and (2) it seems unlikely that an image would be compatible with nVidia
   libraries and have a linker cache but no :code:`ldconfig` executable.

   If the image has no :code:`ldconfig`, :code:`ch-run` exits with an error
   and the container does not run. This indicates the assumption above is
   false, so please report this error as a bug.

Ignored hooks
~~~~~~~~~~~~~

#. :code:`nvidia-ctk-hook create-symlinks`. This creates one or more symlinks.
   In our experience, the links created already exist in the host’s
   :code:`/dev` or are created by :code:`ldconfig(8)`.

#. :code:`nvidia-ctk-hook chmod`. This changes file permissions, but in
   unprivileged Charliecloud containers, the invoking user will already have
   access to all appropriate files.


.. _ch-run_environment-variables:

Environment variables
=====================

Unlike most other implementations, :code:`ch-run`’s baseline for the container
environment is to pass through the host environment unaltered. From this
starting point, the environment is altered in this order:

#. :code:`$HOME`, :code:`$PATH`, and :code:`$TMPDIR` are adjusted to avoid
   common breakage (see below).

#. User-specified changes are executed in the order they appear on the command
   line (i.e., :code:`-d`/:code:`--devices`, :code:`--device`,
   :code:`--set-env`, and :code:`--unset-env`, some of which can appear
   multiple times).

#. :code:`$CH_RUNNING` is set.

Built-in environment changes
----------------------------

Prior to user changes, i.e. can be altered by the user:

:code:`$HOME`
  If :code:`--home` is specified, then your home directory is bind-mounted
  into the guest at :code:`/home/$USER`. If you also have a different home
  directory path on the host, an inherited :code:`$HOME` will be incorrect
  inside the guest, which confuses lots of software, notably Spack. Thus, with
  :code:`--home`, :code:`$HOME` is set to :code:`/home/$USER` (by default, it
  is unchanged.)

:code:`$PATH`
  We append :code:`/bin` to :code:`$PATH` if it’s not already present. This is
  because newer Linux distributions replace some root-level directories, such
  as :code:`/bin`, with symlinks to their counterparts in :code:`/usr`. Some
  of these distributions (e.g., Fedora 24) have also dropped :code:`/bin` from
  the default :code:`$PATH`. This is a problem when the guest OS does *not*
  have a merged :code:`/usr` (e.g., Debian 8 “Jessie”).

  Further reading:

    * `The case for the /usr Merge <https://www.freedesktop.org/wiki/Software/systemd/TheCaseForTheUsrMerge/>`_
    * `Fedora <https://fedoraproject.org/wiki/Features/UsrMove>`_
    * `Debian <https://wiki.debian.org/UsrMerge>`_

:code:`$TMPDIR`
  Unset, because this is almost certainly a host path, and that host path is
  made available in the guest at :code:`/tmp` unless :code:`--private-tmp` is
  given.

After user changes, i.e. cannot be altered by the user with :code:`ch-run`:

:code:`$CH_RUNNING`
  Set to :code:`Weird Al Yankovic`. While a process can figure out that it’s
  in an unprivileged container and what namespaces are active without this
  hint, that can be messy, and there is no way to tell that it’s a
  *Charliecloud* container specifically. This variable makes such a test
  simple and well-defined.

Setting variables with :code:`--set-env` or :code:`--set-env0`
--------------------------------------------------------------

The purpose of these two options is to set environment variables within the
container. Values given replace any already in the environment (i.e.,
inherited from the host shell) or set by earlier uses of the options. These
flags take an optional argument with two possible forms:

1. **If the argument contains an equals sign** (:code:`=`, ASCII 61), that
   sets an environment variable directly. For example, to set :code:`FOO` to
   the string value :code:`bar`::

     $ ch-run --set-env=FOO=bar ...

   Single straight quotes around the value (:code:`'`, ASCII 39) are stripped,
   though be aware that both single and double quotes are also interpreted by
   the shell. For example, this example is similar to the prior one; the
   double quotes are removed by the shell and the single quotes are removed by
   :code:`ch-run`::

     $ ch-run --set-env="'BAZ=qux'" ...

2. **If the argument does not contain an equals sign**, it is a host path to a
   file containing zero or more variables using the same syntax as above
   (except with no prior shell processing).

   With :code:`--set-env`, this file contains a sequence of assignments
   separated by newline (:code:`\n` or ASCII 10); with :code:`--set-env0`, the
   assignments are separated by the null byte (i.e., :code:`\0` or ASCII 0).
   Empty assignments are ignored, and no comments are interpreted. (This
   syntax is designed to accept the output of :code:`printenv` and be easily
   produced by other simple mechanisms.) The file need not be seekable.

   For example::

     $ cat /tmp/env.txt
     FOO=bar
     BAZ='qux'
     $ ch-run --set-env=/tmp/env.txt ...

   For directory images only (because the file is read before containerizing),
   guest paths can be given by prepending the image path.

3. **If there is no argument**, the file :code:`/ch/environment` within the
   image is used. This file is commonly populated by :code:`ENV` instructions
   in the Dockerfile. For example, equivalently to form 2::

     $ cat Dockerfile
     [...]
     ENV FOO=bar
     ENV BAZ=qux
     [...]
     $ ch-image build -t foo .
     $ ch-convert foo /var/tmp/foo.sqfs
     $ ch-run --set-env /var/tmp/foo.sqfs -- ...

   (Note the image path is interpreted correctly, not as the :code:`--set-env`
   argument.)

   At present, there is no way to use files other than :code:`/ch/environment`
   within SquashFS images.

Environment variables are expanded for values that look like search paths,
unless :code:`--env-no-expand` is given prior to :code:`--set-env`. In this
case, the value is a sequence of zero or more possibly-empty items separated
by colon (:code:`:`, ASCII 58). If an item begins with dollar sign (:code:`$`,
ASCII 36), then the rest of the item is the name of an environment variable.
If this variable is set to a non-empty value, that value is substituted for
the item; otherwise (i.e., the variable is unset or the empty string), the
item is deleted, including a delimiter colon. The purpose of omitting empty
expansions is to avoid surprising behavior such as an empty element in
:code:`$PATH` meaning `the current directory
<https://devdocs.io/bash/bourne-shell-variables#PATH>`_.

For example, to set :code:`HOSTPATH` to the search path in the current shell
(this is expanded by :code:`ch-run`, though letting the shell do it happens to
be equivalent)::

  $ ch-run --set-env='HOSTPATH=$PATH' ...

To prepend :code:`/opt/bin` to this current search path::

  $ ch-run --set-env='PATH=/opt/bin:$PATH' ...

To prepend :code:`/opt/bin` to the search path set by the Dockerfile, as
retrieved from guest file :code:`/ch/environment` (here we really cannot let
the shell expand :code:`$PATH`)::

  $ ch-run --set-env --set-env='PATH=/opt/bin:$PATH' ...

Examples of valid assignment, assuming that environment variable :code:`BAR`
is set to :code:`bar` and :code:`UNSET` is unset or set to the empty string:

.. list-table::
   :header-rows: 1

   * - Assignment
     - Name
     - Value
   * - :code:`FOO=bar`
     - :code:`FOO`
     - :code:`bar`
   * - :code:`FOO=bar=baz`
     - :code:`FOO`
     - :code:`bar=baz`
   * - :code:`FLAGS=-march=foo -mtune=bar`
     - :code:`FLAGS`
     - :code:`-march=foo -mtune=bar`
   * - :code:`FLAGS='-march=foo -mtune=bar'`
     - :code:`FLAGS`
     - :code:`-march=foo -mtune=bar`
   * - :code:`FOO=$BAR`
     - :code:`FOO`
     - :code:`bar`
   * - :code:`FOO=$BAR:baz`
     - :code:`FOO`
     - :code:`bar:baz`
   * - :code:`FOO=`
     - :code:`FOO`
     - empty string
   * - :code:`FOO=$UNSET`
     - :code:`FOO`
     - empty string
   * - :code:`FOO=baz:$UNSET:qux`
     - :code:`FOO`
     - :code:`baz:qux` (not :code:`baz::qux`)
   * - :code:`FOO=:bar:baz::`
     - :code:`FOO`
     - :code:`:bar:baz::`
   * - :code:`FOO=''`
     - :code:`FOO`
     - empty string
   * - :code:`FOO=''''`
     - :code:`FOO`
     - :code:`''` (two single quotes)

Example invalid assignments:

.. list-table::
   :header-rows: 1

   * - Assignment
     - Problem
   * - :code:`FOO bar`
     - no equals separator
   * - :code:`=bar`
     - name cannot be empty

Example valid assignments that are probably not what you want:

.. Note: Plain leading space screws up ReST parser. We use ZERO WIDTH SPACE
   U+200B, then plain space. This will copy and paste incorrectly, but that
   seems unlikely.

.. list-table::
   :header-rows: 1

   * - Assignment
     - Name
     - Value
     - Problem
   * - :code:`FOO="bar"`
     - :code:`FOO`
     - :code:`"bar"`
     - double quotes aren’t stripped
   * - :code:`FOO=bar # baz`
     - :code:`FOO`
     - :code:`bar # baz`
     - comments not supported
   * - :code:`FOO=bar\tbaz`
     - :code:`FOO`
     - :code:`bar\tbaz`
     - backslashes are not special
   * - :code:`​ FOO=bar`
     - :code:`​ FOO`
     - :code:`bar`
     - leading space in key
   * - :code:`FOO= bar`
     - :code:`FOO`
     - :code:`​ bar`
     - leading space in value
   * - :code:`$FOO=bar`
     - :code:`$FOO`
     - :code:`bar`
     - variables not expanded in key
   * - :code:`FOO=$BAR baz:qux`
     - :code:`FOO`
     - :code:`qux`
     - variable :code:`BAR baz` not set

Removing variables with :code:`--unset-env`
-------------------------------------------

The purpose of :code:`--unset-env=GLOB` is to remove unwanted environment
variables. The argument :code:`GLOB` is a glob pattern (`dialect
<http://man7.org/linux/man-pages/man3/fnmatch.3.html>`_ :code:`fnmatch(3)`
with the :code:`FNM_EXTMATCH` flag where supported); all variables with
matching names are removed from the environment.

.. warning::

   Because the shell also interprets glob patterns, if any wildcard characters
   are in :code:`GLOB`, it is important to put it in single quotes to avoid
   surprises.

:code:`GLOB` must be a non-empty string.

Example 1: Remove the single environment variable :code:`FOO`::

  $ export FOO=bar
  $ env | fgrep FOO
  FOO=bar
  $ ch-run --unset-env=FOO $CH_TEST_IMGDIR/chtest -- env | fgrep FOO
  $

Example 2: Hide from a container the fact that it’s running in a Slurm
allocation, by removing all variables beginning with :code:`SLURM`. You might
want to do this to test an MPI program with one rank and no launcher::

  $ salloc -N1
  $ env | egrep '^SLURM' | wc
     44      44    1092
  $ ch-run $CH_TEST_IMGDIR/mpihello-openmpi -- /hello/hello
  [... long error message ...]
  $ ch-run --unset-env='SLURM*' $CH_TEST_IMGDIR/mpihello-openmpi -- /hello/hello
  0: MPI version:
  Open MPI v3.1.3, package: Open MPI root@c897a83f6f92 Distribution, ident: 3.1.3, repo rev: v3.1.3, Oct 29, 2018
  0: init ok cn001.localdomain, 1 ranks, userns 4026532530
  0: send/receive ok
  0: finalize ok

Example 3: Clear the environment completely (remove all variables)::

  $ ch-run --unset-env='*' $CH_TEST_IMGDIR/chtest -- env
  $

Example 4: Remove all environment variables *except* for those prefixed with
either :code:`WANTED_` or :code:`ALSO_WANTED_`::

  $ export WANTED_1=yes
  $ export ALSO_WANTED_2=yes
  $ export NOT_WANTED_1=no
  $ ch-run --unset-env='!(WANTED_*|ALSO_WANTED_*)' $CH_TEST_IMGDIR/chtest -- env
  WANTED_1=yes
  ALSO_WANTED_2=yes
  $

Note that some programs, such as shells, set some environment variables even
if started with no init files::

  $ ch-run --unset-env='*' $CH_TEST_IMGDIR/debian_9ch -- bash --noprofile --norc -c env
  SHLVL=1
  PWD=/
  _=/usr/bin/env
  $


Examples
========

Run the command :code:`echo hello` inside a Charliecloud container using the
unpacked image at :code:`/data/foo`::

    $ ch-run /data/foo -- echo hello
    hello

Run an MPI job that can use CMA to communicate::

    $ srun ch-run --join /data/foo -- bar


Syslog
======

By default, :code:`ch-run` logs its command line to `syslog
<https://en.wikipedia.org/wiki/Syslog>`_. (This can be disabled by configuring
with :code:`--disable-syslog`.) This includes: (1) the invoking real UID, (2)
the number of command line arguments, and (3) the arguments, separated by
spaces. For example::

  Dec 10 18:19:08 mybox ch-run: uid=1000 args=7: ch-run -v /var/tmp/00_tiny -- echo hello "wor l}\$d"

Logging is one of the first things done during program initialization, even
before command line parsing. That is, almost all command lines are logged,
even if erroneous, and there is no logging of program success or failure.

Arguments are serialized with the following procedure. The purpose is to
provide a human-readable reconstruction of the command line while also
allowing each argument to be recovered byte-for-byte.

  .. Note: The next paragraph contains ​U+200B ZERO WIDTH SPACE after the
     backslash because backslash by itself won’t build and two backslashes
     renders as two backslashes.

  * If an argument contains only printable ASCII bytes that are not
    whitespace, shell metacharacters, double quote (:code:`"`, ASCII 34
    decimal), or backslash (:code:`\​`, ASCII 92), then log it unchanged.

  * Otherwise, (a) enclose the argument in double quotes and
    (b) backslash-escape double quotes, backslashes, and characters
    interpreted by Bash (including POSIX shells) within double quotes.

The verbatim command line typed in the shell cannot be recovered, because not
enough information is provided to UNIX programs. For example,
:code:`echo  'foo'` is given to programs as a sequence of two arguments,
:code:`echo` and :code:`foo`; the two spaces and single quotes are removed by
the shell. The zero byte, ASCII NUL, cannot appear in arguments because it
would terminate the string.

Exit status
===========

If there is an error during containerization, :code:`ch-run` exits with status
non-zero. If the user command is started successfully, the exit status is that
of the user command, with one exception: if the image is an internally mounted
SquashFS filesystem and the user command is killed by a signal, the exit
status is 1 regardless of the signal value.


.. include:: ./bugs.rst
.. include:: ./see_also.rst

..  LocalWords:  mtune NEWROOT hugetlbfs UsrMerge fusermount mybox IMG HOSTPATH
..  LocalWords:  noprofile norc SHLVL PWD kernelnewbies extglob cdi AMMVs dri
..  LocalWords:  Desiniotis declarativeness fabricmanager libglxserver ctk
..  LocalWords:  libcuda ldcache
