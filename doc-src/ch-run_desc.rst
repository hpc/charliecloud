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

* If :code:`--join-ct` is too high or :code:`ch-run` itself crashes, IPC
  resources such as semaphores and shared memory segments will be leaked. The
  utilities :code:`ipcs(1)` and :code:`ipcrm(1)` can be used to clean up.

Examples
========

Run the command :code:`echo hello` inside a Charliecloud container using the
unpacked image at :code:`/data/foo`::

    $ ch-run /data/foo -- echo hello
    hello

Run an MPI job that can use CMA to communicate::

    $ srun ch-run --join /data/foo -- bar
