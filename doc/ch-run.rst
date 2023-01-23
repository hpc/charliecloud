:code:`ch-run`
++++++++++++++

.. only:: not man

   Run a command in a Charliecloud container.


Synopsis
========

::

  $ ch-run [OPTION...] IMAGE -- CMD [ARG...]


Description
===========

Run command :code:`CMD` in a fully unprivileged Charliecloud container using
the image specified by :code:`IMAGE`, which can be: (1) a path to a directory,
(2) the name of an image in :code:`ch-image` storage (e.g.
:code:`example.com:5050/foo`) or, if the proper support is enabled, a SquashFS
archive. :code:`ch-run` does not use any setuid or setcap helpers, even for
mounting SquashFS images with FUSE.

  :code:`-b`, :code:`--bind=SRC[:DST]`
    Bind-mount :code:`SRC` at guest :code:`DST`. The default destination if
    not specified is to use the same path as the host; i.e., the default is
    :code:`--bind=SRC:SRC`. Can be repeated.

    If :code:`--write` is given and :code:`DST` does not exist, it will be
    created as an empty directory. However, :code:`DST` must be entirely
    within the image itself; :code:`DST` cannot enter a previous bind mount.
    For example, :code:`--bind /foo:/tmp/foo` will fail because :code:`/tmp`
    is shared with the host via bind-mount (unless :code:`$TMPDIR` is set to
    something else or :code:`--private-tmp` is given).

    Most images do have ten directories :code:`/mnt/[0-9]` already available
    as mount points.

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

  :code:`--ch-ssh`
    Bind :code:`ch-ssh(1)` into container at :code:`/usr/bin/ch-ssh`.

  :code:`--env-no-expand`
    Don’t expand variables when using :code:`--set-env`.

  :code:`--fake-syscalls`
    Using seccomp, intercept some system calls that would fail due to lack of
    privilege, do nothing, and return fake success to the calling program.
    This is intended for use by :code:`ch-image(1)` when building images; see
    that man page for a detailed discussion.

  :code:`-g`, :code:`--gid=GID`
    Run as group :code:`GID` within container.

  :code:`--home`
    Bind-mount your host home directory (i.e., :code:`$HOME`) at guest
    :code:`/home/$USER`. This is accomplished by over-mounting a new
    :code:`tmpfs` at :code:`/home`, which hides any image content under that
    path. By default, neither of these things happens and the image’s
    :code:`/home` is exposed unaltered.

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

  :code:`-s`, :code:`--storage DIR`
    Set the storage directory. Equivalent to the same option for
    :code:`ch-image(1)`.

  :code:`-t`, :code:`--private-tmp`
    By default, the host’s :code:`/tmp` (or :code:`$TMPDIR` if set) is
    bind-mounted at container :code:`/tmp`. If this is specified, a new
    :code:`tmpfs` is mounted on the container’s :code:`/tmp` instead.

  :code:`--set-env`, :code:`--set-env=FILE`, :code:`--set-env=VAR=VALUE`
    Set environment variable(s). With:

       * no argument: as listed in file :code:`/ch/environment` within the
         image. It is an error if the file does not exist or cannot be read.
         (Note that with SquashFS images, it is not currently possible to use
         other files within the image.)

       * :code:`FILE` (i.e., no equals in argument): as specified in file at
         host path :code:`FILE`. Again, it is an error if the file cannot be
         read.

       * :code:`NAME=VALUE` (i.e., equals sign in argument): set variable
         :code:`NAME` to :code:`VALUE`.

    See below for details on how environment variables work in :code:`ch-run`.

  :code:`-u`, :code:`--uid=UID`
    Run as user :code:`UID` within container.

  :code:`--unsafe`
    Enable various unsafe behavior. For internal use only. Seriously, stay
    away from this option.

  :code:`--unset-env=GLOB`
    Unset environment variables whose names match :code:`GLOB`.

  :code:`-v`, :code:`--verbose`
    Be more verbose (can be repeated).

  :code:`-w`, :code:`--write`
    Mount image read-write (by default, the image is mounted read-only).

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
   :code:`CMD`’s process exits. It does not monitor any of its child
   processes. Therefore, if the user command spawns child processes and then
   exits before them (e.g., some daemons), those children will have the image
   unmounted from underneath them. In this case, the workaround is to
   mount/unmount using external tools. We expect to remove this limitation in
   a future version.


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

  * :code:`$PREFIX/bin/ch-ssh` at guest :code:`/usr/bin/ch-ssh`. SSH wrapper
    that automatically containerizes after connecting.

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


Environment variables
=====================

:code:`ch-run` leaves environment variables unchanged, i.e. the host
environment is passed through unaltered, except:

* limited tweaks to avoid significant guest breakage;
* user-set variables via :code:`--set-env`;
* user-unset variables via :code:`--unset-env`; and
* set :code:`CH_RUNNING`.

This section describes these features.

The default tweaks happen first, then :code:`--set-env` and
:code:`--unset-env` in the order specified on the command line, and then
:code:`CH_RUNNING`. The two options can be repeated arbitrarily many times,
e.g. to add/remove multiple variable sets or add only some variables in a
file.

Default behavior
----------------

By default, :code:`ch-run` makes the following environment variable changes:

:code:`$CH_RUNNING`
  Set to :code:`Weird Al Yankovic`. While a process can figure out that it’s
  in an unprivileged container and what namespaces are active without this
  hint, that can be messy, and there is no way to tell that it’s a
  *Charliecloud* container specifically. This variable makes such a test
  simple and well-defined. (**Note:** This variable is unaffected by
  :code:`--unset-env`.)

:code:`$HOME`
  If :code:`--home` is specified, then your home directory is bind-mounted
  into the guest at :code:`/home/$USER`. If you also have a different home
  directory path on the host, an inherited :code:`$HOME` will be incorrect
  inside the guest, which confuses lots of software, notably Spack. Thus, with
  :code:`--home`, :code:`$HOME` is set to :code:`/home/$USER` (by default, it
  is unchanged.)

:code:`$PATH`
  Newer Linux distributions replace some root-level directories, such as
  :code:`/bin`, with symlinks to their counterparts in :code:`/usr`.

  Some of these distributions (e.g., Fedora 24) have also dropped :code:`/bin`
  from the default :code:`$PATH`. This is a problem when the guest OS does
  *not* have a merged :code:`/usr` (e.g., Debian 8 “Jessie”). Thus, we add
  :code:`/bin` to :code:`$PATH` if it’s not already present.

  Further reading:

    * `The case for the /usr Merge <https://www.freedesktop.org/wiki/Software/systemd/TheCaseForTheUsrMerge/>`_
    * `Fedora <https://fedoraproject.org/wiki/Features/UsrMove>`_
    * `Debian <https://wiki.debian.org/UsrMerge>`_

:code:`$TMPDIR`
  Unset, because this is almost certainly a host path, and that host path is
  made available in the guest at :code:`/tmp` unless :code:`--private-tmp` is
  given.

Setting variables with :code:`--set-env`
----------------------------------------

The purpose of :code:`--set-env` is to set environment variables within the
container. Values given replace any already in the environment (i.e.,
inherited from the host shell) or set by earlier :code:`--set-env`. This flag
takes an optional argument with two possible forms:

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
   (except with no prior shell processing). This file contains a sequence of
   assignments separated by newlines. Empty lines are ignored, and no comments
   are interpreted. (This syntax is designed to accept the output of
   :code:`printenv` and be easily produced by other simple mechanisms.) For
   example::

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
     - double quotes aren't stripped
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
..  LocalWords:  noprofile norc SHLVL PWD
