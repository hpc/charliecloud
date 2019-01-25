Synopsis
========

::

  $ ch-run [OPTION...] NEWROOT CMD [ARG...]

Description
===========

Run command :code:`CMD` in a Charliecloud container using the flattened and
unpacked image directory located at :code:`NEWROOT`.

  :code:`-b`, :code:`--bind=SRC[:DST]`
    mount :code:`SRC` at guest :code:`DST` (default :code:`/mnt/0`,
    :code:`/mnt/1`, etc.)

  :code:`-c`, :code:`--cd=DIR`
    initial working directory in container

  :code:`-g`, :code:`--gid=GID`
    run as group :code:`GID` within container

  :code:`-j`, :code:`--join`
    use the same container (namespaces) as peer :code:`ch-run` invocations

  :code:`--join-pid=PID`
    join the namespaces of an existing process

  :code:`--join-ct=N`
    number of :code:`ch-run` peers (implies :code:`--join`; default: see below)

  :code:`--join-tag=TAG`
    label for :code:`ch-run` peer group (implies :code:`--join`; default: see
    below)

  :code:`--no-home`
    do not bind-mount your home directory (by default, your home directory is
    mounted at :code:`/home/$USER` in the container)

  :code:`-t`, :code:`--private-tmp`
    use container-private :code:`/tmp` (by default, :code:`/tmp` is shared with
    the host)

  :code:`--set-env=FILE`
    set environment variables as specified in host path :code:`FILE`

  :code:`-u`, :code:`--uid=UID`
    run as user :code:`UID` within container

  :code:`-v`, :code:`--verbose`
    be more verbose (debug if repeated)

  :code:`-w`, :code:`--write`
    mount image read-write (by default, the image is mounted read-only)

  :code:`-?`, :code:`--help`
    print help and exit

  :code:`--usage`
    print a short usage message and exit

  :code:`-V`, :code:`--version`
    print version and exit

Host files and directories available in container via bind mounts
=================================================================

In addition to any directories specified by the user with :code:`--bind`,
:code:`ch-run` has standard host files and directories that are bind-mounted
in as well.

The following host files and directories are bind-mounted at the same location
in the container. These cannot be disabled.

  * :code:`/dev`
  * :code:`/etc/passwd`
  * :code:`/etc/group`
  * :code:`/etc/hosts`
  * :code:`/etc/resolv.conf`
  * :code:`/proc`
  * :code:`/sys`

Three additional bind mounts can be disabled by the user:

  * Your home directory (i.e., :code:`$HOME`) is mounted at guest
    :code:`/home/$USER` by default. This is accomplished by mounting a new
    :code:`tmpfs` at :code:`/home`, which hides any image content under that
    path. If :code:`--no-home` is specified, neither of these things happens
    and the image's :code:`/home` is exposed unaltered.

  * :code:`/tmp` is shared with the host by default. If :code:`--private-tmp`
    is specified, a new :code:`tmpfs` is mounted on the guest's :code:`/tmp`
    instead.

  * If file :code:`/usr/bin/ch-ssh` is present in the image, it is
    over-mounted with the :code:`ch-ssh` binary in the same directory as
    :code:`ch-run`.

Multiple processes in the same container with :code:`--join`
=============================================================

By default, different :code:`ch-run` invocations use different user and mount
namespaces (i.e., different containers). While this has no impact on sharing
most resources between invocations, there are a few important exceptions.
These include:

1. :code:`ptrace(2)`, used by debuggers and related tools. One can attach a
   debugger to processes in descendant namespaces, but not sibling namespaces.
   The practical effect of this is that (without :code:`--join`), you can't
   run a command with :code:`ch-run` and then attach to it with a debugger
   also run with :code:`ch-run`.

2. *Cross-memory attach* (CMA) is used by cooperating processes to communicate
   by simply reading and writing one another's memory. This is also not
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
  of :code:`ch-run`'s parent. Tags can be re-used for peer groups that start
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

* If :code:`--join-ct` is too high, the winning :code:`ch-run`'s user command
  exits before all peers join, or :code:`ch-run` itself crashes, IPC resources
  such as semaphores and shared memory segments will be leaked. These appear
  as files in :code:`/dev/shm/` and can be removed with :code:`rm(1)`.

* Many of the arguments given to the race losers, such as the image path and
  :code:`--bind`, will be ignored in favor of what was given to the winner.

Environment variables
=====================

:code:`ch-run` leaves environment variables unchanged, i.e. the host
environment is passed through unaltered, except:

* limited tweaks to avoid significant guest breakage; and
* user-set variables via :code:`--set-env`

This section describes these features.

The default tweaks happen first, followed by :code:`--set-env`. The
latter can be repeated arbitrarily many times, e.g. to add multiple
variable sets.

Default behavior
----------------

By default, :code:`ch-run` makes the following environment variable changes:

* :code:`$HOME`: If the path to your home directory is not :code:`/home/$USER`
  on the host, then an inherited :code:`$HOME` will be incorrect inside the
  guest. This confuses some software, such as Spack.

  Thus, we change :code:`$HOME` to :code:`/home/$USER`, unless
  :code:`--no-home` is specified, in which case it is left unchanged.

* :code:`$PATH`: Newer Linux distributions replace some root-level
  directories, such as :code:`/bin`, with symlinks to their counterparts in
  :code:`/usr`.

  Some of these distributions (e.g., Fedora 24) have also dropped :code:`/bin`
  from the default :code:`$PATH`. This is a problem when the guest OS does
  *not* have a merged :code:`/usr` (e.g., Debian 8 “Jessie”). Thus, we add
  :code:`/bin` to :code:`$PATH` if it's not already present.

  Further reading:

    * `The case for the /usr Merge <https://www.freedesktop.org/wiki/Software/systemd/TheCaseForTheUsrMerge/>`_
    * `Fedora <https://fedoraproject.org/wiki/Features/UsrMove>`_
    * `Debian <https://wiki.debian.org/UsrMerge>`_

Setting environment variables with :code:`--set-env`
---------------------------------------------------------

The purpose of :code:`--set-env=FILE` is to set environment variables that
cannot be inherited from the host shell, e.g. Dockerfile :code:`ENV`
directives or other build-time configuration. :code:`FILE` is a host path to
provide the greatest flexibility; guest paths can be specified by prepending
the image path.

Variable values in :code:`FILE` replace any already set. If a variable is
repeated, the last value wins.

The syntax of :code:`FILE` is key-value pairs separated by the first equals
character (:code:`=`, ASCII 61), one per line, with optional single straight
quotes (:code:`'`, ASCII 39) around the value. Empty lines are ignored.
Newlines (ASCII 10) are not permitted in either key or value. No variable
expansion, comments, etc. are provided. The value may be empty, but not the
key. (This syntax is designed to accept the output of :code:`printenv` and be
easily produced by other simple mechanisms.) Examples of valid lines:

.. list-table::
   :header-rows: 1

   * - Line
     - Key
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
   * - :code:`FOO=`
     - :code:`FOO`
     - (empty string)
   * - :code:`FOO=''`
     - :code:`FOO`
     - (empty string)
   * - :code:`FOO=''''`
     - :code:`FOO`
     - :code:`''` (two single quotes)

Example invalid lines:

.. list-table::
   :header-rows: 1

   * - Line
     - Problem
   * - :code:`FOO bar`
     - no separator
   * - :code:`=bar`
     - key cannot be empty

Example valid lines that are probably not what you want:

.. Note: Plain leading space screws up ReST parser. We use ZERO WIDTH SPACE
   U+200B, then plain space. This will copy and paste incorrectly, but that
   seems unlikely.

.. list-table::
   :header-rows: 1

   * - Line
     - Key
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
   * - :code:`PATH=$PATH:/opt/bin`
     - :code:`PATH`
     - :code:`$PATH:/opt/bin`
     - variables not expanded
   * - :code:`​ FOO=bar`
     - :code:`​ FOO`
     - :code:`bar`
     - leading space in key
   * - :code:`FOO= bar`
     - :code:`FOO`
     - :code:`​ bar`
     - leading space in value

Example Docker command to produce a valid :code:`FILE`::

  $ docker inspect $TAG --format='{{range .Config.Env}}{{println .}}{{end}}'

Examples
========

Run the command :code:`echo hello` inside a Charliecloud container using the
unpacked image at :code:`/data/foo`::

    $ ch-run /data/foo -- echo hello
    hello

Run an MPI job that can use CMA to communicate::

    $ srun ch-run --join /data/foo -- bar

..  LocalWords:  mtune
