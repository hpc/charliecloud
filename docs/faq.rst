Frequently asked questions (FAQ)
********************************

.. contents::
   :depth: 3
   :local:


About the project
=================

Where did the name Charliecloud come from?
------------------------------------------

*Charlie* — Charles F. McMillan was director of Los Alamos National Laboratory
from June 2011 until December 2017, i.e., at the time Charliecloud was started
in early 2014. He is universally referred to as “Charlie” here.

*cloud* — Charliecloud provides cloud-like flexibility for HPC systems.

How do you spell Charliecloud?
------------------------------

We try to be consistent with *Charliecloud* — one word, no camel case. That
is, *Charlie Cloud* and *CharlieCloud* are both incorrect.


Errors
======

How do I read the :code:`ch-run` error messages?
------------------------------------------------

:code:`ch-run` error messages look like this::

  $ ch-run foo -- echo hello
  ch-run[25750]: can't find image: foo: No such file or directory (ch-run.c:107 2)

There is a lot of information here, and it comes in this order:

1. Name of the executable; always :code:`ch-run`.

2. Process ID in square brackets; here :code:`25750`. This is useful when
   debugging parallel :code:`ch-run` invocations.

3. Colon.

4. Main error message; here :code:`can't find image: foo`. This should be
   informative as to what went wrong, and if it’s not, please file an issue,
   because you may have found a usability bug. Note that in some cases you may
   encounter the default message :code:`error`; if this happens and you’re not
   doing something very strange, that’s also a usability bug.

5. Colon (but note that the main error itself can contain colons too), if and
   only if the next item is present.

6. Operating system’s description of the the value of :code:`errno`; here
   :code:`No such file or directory`. Omitted if not applicable.

7. Open parenthesis.

8. Name of the source file where the error occurred; here :code:`ch-run.c`.
   This and the following item tell developers exactly where :code:`ch-run`
   became confused, which greatly improves our ability to provide help and/or
   debug.

9. Source line where the error occurred.

10. Value of :code:`errno` (see `C error codes in Linux
    <http://www.virtsync.com/c-error-codes-include-errno>`_ for the full
    list of possibilities).

11. Close parenthesis.

*Note:* Despite the structured format, the error messages are not guaranteed
to be machine-readable.

Tarball build fails with “No command specified”
-----------------------------------------------

The full error from :code:`ch-builder2tar` or :code:`ch-build2dir` is::

  docker: Error response from daemon: No command specified.

You will also see it with various plain Docker commands.

This happens when there is no default command specified in the Dockerfile or
any of its ancestors. Some base images specify one (e.g., Debian) and others
don’t (e.g., Alpine). Docker requires this even for commands that don’t seem
like they should need it, such as :code:`docker create` (which is what trips
up Charliecloud).

The solution is to add a default command to your Dockerfile, such as
:code:`CMD ["true"]`.

:code:`ch-run` fails with “can't re-mount image read-only”
----------------------------------------------------------

Normally, :code:`ch-run` re-mounts the image directory read-only within the
container. This fails if the image resides on certain filesystems, such as NFS
(see `issue #9 <https://github.com/hpc/charliecloud/issues/9>`_). There are
two solutions:

1. Unpack the image into a different filesystem, such as :code:`tmpfs` or
   local disk. Consult your local admins for a recommendation. Note that
   Lustre is probably not a good idea because it can give poor performance for
   you and also everyone else on the system.

2. Use the :code:`-w` switch to leave the image mounted read-write. This may
   have an impact on reproducibility (because the application can change the
   image between runs) and/or stability (if there are multiple application
   processes and one writes a file in the image that another is reading or
   writing).


Unexpected behavior
===================

What do the version numbers mean?
---------------------------------

Released versions of Charliecloud have a pretty standard version number, e.g.
0.9.7.

Work leading up to a released version also has version numbers, to satisfy
tools that require them and to give the executables something useful to report
on :code:`--version`, but these can be quite messy. We refer to such versions
informally as *pre-releases*, but Charliecloud does not have formal
pre-releases such as alpha, beta, or release candidate.

*Pre-release version numbers are not in order*, because this work is in a DAG
rather than linear, except they precede the version we are working towards. If
you're dealing with these versions, use Git.

Pre-release version numbers are the version we are working towards, followed
by: :code:`~pre`, the branch name if not :code:`master` with non-alphanumerics
removed, the commit hash, and finally :code:`dirty` if the working directory
had uncommitted changes.

Examples:

  * :code:`0.2.0` : Version 0.2.0. Released versions don't include Git
    information, even if built in a Git working directory.

  * :code:`0.2.1~pre` : Some snapshot of work leading up to 0.2.1, built from
    source code where the Git information has been lost, e.g. the tarballs
    Github provides. This should make you wary because you don't have any
    provenance. It might even be uncommitted work or an abandoned branch.

  * :code:`0.2.1~pre.1a99f42` : Master branch commit 1a99f42, built from a
    clean working directory (i.e., no changes since that commit).

  * :code:`0.2.1~pre.foo1.0729a78` : Commit 0729a78 on branch :code:`foo-1`,
    :code:`foo_1`, etc. built from clean working directory.

  * :code:`0.2.1~pre.foo1.0729a78.dirty` : Commit 0729a78 on one of those
    branches, plus un-committed changes.

:code:`--uid 0` lets me read files I can’t otherwise!
-----------------------------------------------------

Some permission bits can give a surprising result with a container UID of 0.
For example::

  $ whoami
  reidpr
  $ echo surprise > ~/cantreadme
  $ chmod 000 ~/cantreadme
  $ ls -l ~/cantreadme
  ---------- 1 reidpr reidpr 9 Oct  3 15:03 /home/reidpr/cantreadme
  $ cat ~/cantreadme
  cat: /home/reidpr/cantreadme: Permission denied
  $ ch-run /var/tmp/hello cat ~/cantreadme
  cat: /home/reidpr/cantreadme: Permission denied
  $ ch-run --uid 0 /var/tmp/hello cat ~/cantreadme
  surprise

At first glance, it seems that we’ve found an escalation -- we were able to
read a file inside a container that we could not read on the host! That seems
bad.

However, what is really going on here is more prosaic but complicated:

1. After :code:`unshare(CLONE_NEWUSER)`, :code:`ch-run` gains all capabilities
   inside the namespace. (Outside, capabilities are unchanged.)

2. This include :code:`CAP_DAC_OVERRIDE`, which enables a process to
   read/write/execute a file or directory mostly regardless of its permission
   bits. (This is why root isn’t limited by permissions.)

3. Within the container, :code:`exec(2)` capability rules are followed.
   Normally, this basically means that all capabilities are dropped when
   :code:`ch-run` replaces itself with the user command. However, if EUID is
   0, which it is inside the namespace given :code:`--uid 0`, then the
   subprocess keeps all its capabilities. (This makes sense: if root creates a
   new process, it stays root.)

4. :code:`CAP_DAC_OVERRIDE` within a user namespace is honored for a file or
   directory only if its UID and GID are both mapped. In this case,
   :code:`ch-run` maps :code:`reidpr` to container :code:`root` and group
   :code:`reidpr` to itself.

5. Thus, files and directories owned by the host EUID and EGID (here
   :code:`reidpr:reidpr`) are available for all access with :code:`ch-run
   --uid 0`.

This is not an escalation. The quirk applies only to files owned by the
invoking user, because :code:`ch-run` is unprivileged outside the namespace,
and thus he or she could simply :code:`chmod` the file to read it. Access
inside and outside the container remains equivalent.

References:

* http://man7.org/linux/man-pages/man7/capabilities.7.html
* http://lxr.free-electrons.com/source/kernel/capability.c?v=4.2#L442
* http://lxr.free-electrons.com/source/fs/namei.c?v=4.2#L328

Why does :code:`ping` not work?
-------------------------------

:code:`ping` fails with “permission denied” or similar under Charliecloud,
even if you’re UID 0 inside the container::

  $ ch-run $IMG -- ping 8.8.8.8
  PING 8.8.8.8 (8.8.8.8): 56 data bytes
  ping: permission denied (are you root?)
  $ ch-run --uid=0 $IMG -- ping 8.8.8.8
  PING 8.8.8.8 (8.8.8.8): 56 data bytes
  ping: permission denied (are you root?)

This is because :code:`ping` needs a raw socket to construct the needed
:code:`ICMP ECHO` packets, which requires capability :code:`CAP_NET_RAW` or
root. Unprivileged users can normally use :code:`ping` because it’s a setuid
or setcap binary: it raises privilege using the filesystem bits on the
executable to obtain a raw socket.

Under Charliecloud, there are multiple reasons :code:`ping` can’t get a raw
socket. First, images are unpacked without privilege, meaning that setuid and
setcap bits are lost. But even if you do get privilege in the container (e.g.,
with :code:`--uid=0`), this only applies in the container. Charliecloud uses
the host’s network namespace, where your unprivileged host identity applies
and :code:`ping` still can’t get a raw socket.

The recommended alternative is to simply try the thing you want to do, without
testing connectivity using :code:`ping` first.

Why is MATLAB trying and failing to change the group of :code:`/dev/pts/0`?
---------------------------------------------------------------------------

MATLAB and some other programs want pseudo-TTY (PTY) files to be group-owned
by :code:`tty`. If it’s not, Matlab will attempt to :code:`chown(2)` the file,
which fails inside a container.

The scenario in more detail is this. Assume you’re user :code:`charlie`
(UID=1000), your primary group is :code:`nerds` (GID=1001), :code:`/dev/pts/0`
is the PTY file in question, and its ownership is :code:`charlie:tty`
(:code:`1000:5`), as it should be. What happens in the container by default
is:

1. MATLAB :code:`stat(2)`\ s :code:`/dev/pts/0` and checks the GID.

2. This GID is :code:`nogroup` (65534) because :code:`tty` (5) is not mapped
   on the host side (and cannot be, because only one’s EGID can be mapped in
   an unprivileged user namespace).

3. MATLAB concludes this is bad.

4. MATLAB executes :code:`chown("/dev/pts/0", 1000, 5)`.

5. This fails because GID 5 is not mapped on the guest side.

6. MATLAB pukes.

The workaround is to map your EGID of 1001 to 5 inside the container (instead
of the default 1001:1001), i.e. :code:`--gid=5`. Then, step 4 succeeds because
the call is mapped to :code:`chown("/dev/pts/0", 1000, 1001)` and MATLAB is
happy.

.. _faq_docker2tar-size:

:code:`ch-builder2tar` gives incorrect image sizes
--------------------------------------------------

:code:`ch-builder2tar` often finishes before the progress bar is complete. For
example::

  $ ch-builder2tar mpihello /var/tmp
   373MiB 0:00:21 [============================>                 ] 65%
  146M /var/tmp/mpihello.tar.gz

In this case, the :code:`.tar.gz` contains 392 MB uncompressed::

  $ zcat /var/tmp/mpihello.tar.gz | wc
  2740966 14631550 392145408

But Docker thinks the image is 597 MB::

  $ sudo docker image inspect mpihello | fgrep -i size
          "Size": 596952928,
          "VirtualSize": 596952928,

We've also seen cases where the Docker-reported size is an *under*\ estimate::

  $ ch-builder2tar spack /var/tmp
   423MiB 0:00:22 [============================================>] 102%
  162M /var/tmp/spack.tar.gz
  $ zcat /var/tmp/spack.tar.gz | wc
  4181186 20317858 444212736
  $ sudo docker image inspect spack | fgrep -i size
          "Size": 433812403,
          "VirtualSize": 433812403,

We think that this is because Docker is computing size based on the size of
the layers rather than the unpacked image. We do not currently have a fix; see
`issue #165 <https://github.com/hpc/charliecloud/issues/165>`_.

My second-level directory :code:`dev` is empty
----------------------------------------------

Some image tarballs, such as official Ubuntu Docker images, put device files
in :code:`/dev`. These files prevent unpacking the tarball, because
unprivileged users cannot create device files. Further, these files are not
needed because :code:`ch-run` overmounts :code:`/dev` anyway.

We cannot reliably prevent device files from being included in the tar,
because often that is outside our control, e.g. :code:`docker export` produces
a tarball. Thus, we must exclude them at unpacking time.

An additional complication is that :code:`ch-tar2dir` can handle tarballs both
with a single top-level directory and without, i.e. “tarbombs”. For example,
best practice use of :code:`tar` on the command line produces the former,
while :code:`docker export` (perhaps via :code:`ch-builder2tar`) produces a
tarbomb.

Thus, :code:`ch-tar2dir` uses :code:`tar --exclude` to exclude from unpacking
everything under :code:`./dev` and :code:`*/dev`, i.e., directory :code:`dev`
appearing at either the first or second level are forced to be empty.

This yields false positives if you have a tarbomb image with a directory
:code:`dev` at the second level containing stuff you care about. Hopefully
this is rare, but please let us know if it is your use case.

My password that contains digits doesn't work in VirtualBox console
-------------------------------------------------------------------

VirtualBox has confusing Num Lock behavior. Thus, you may be typing arrows,
page up/down, etc. instead of digits, without noticing because console
password fields give no feedback, not even whether a character has been typed.

Try using the number row instead, toggling Num Lock key, or SSHing into the
virtual machine.


How do I ...
============

My app needs to write to :code:`/var/log`, :code:`/run`, etc.
-------------------------------------------------------------

Because the image is mounted read-only by default, log files, caches, and
other stuff cannot be written anywhere in the image. You have three options:

1. Configure the application to use a different directory. :code:`/tmp` is
   often a good choice, because it’s shared with the host and fast.

2. Use :code:`RUN` commands in your Dockerfile to create symlinks that point
   somewhere writeable, e.g. :code:`/tmp`, or :code:`/mnt/0` with
   :code:`ch-run --bind`.

3. Run the image read-write with :code:`ch-run -w`. Be careful that multiple
   containers do not try to write to the same files.

Which specific :code:`sudo` commands are needed?
------------------------------------------------

For running images, :code:`sudo` is not needed at all.

For building images, it depends on what you would like to support. For
example, do you want to let users build images with Docker? Do you want to let
them run the build tests?

We do not maintain specific lists, but you can search the source code and
documentation for uses of :code:`sudo` and :code:`$DOCKER` and evaluate them
on a case-by-case basis. (The latter includes :code:`sudo` if needed to invoke
:code:`docker` in your environment.) For example::

  $ find . \(   -type f -executable \
             -o -name Makefile \
             -o -name '*.bats' \
             -o -name '*.rst' \
             -o -name '*.sh' \) \
           -exec egrep -H '(sudo|\$DOCKER)' {} \;

OpenMPI Charliecloud jobs don’t work
------------------------------------

MPI can be finicky. This section documents some of the problems we’ve seen.

:code:`mpirun` can’t launch jobs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

For example, you might see::

  $ mpirun -np 1 ch-run /var/tmp/mpihello -- /hello/hello
  App launch reported: 2 (out of 2) daemons - 0 (out of 1) procs
  [cn001:27101] PMIX ERROR: BAD-PARAM in file src/dstore/pmix_esh.c at line 996

We’re not yet sure why this happens — it may be a mismatch between the OpenMPI
builds inside and outside the container — but in our experience launching with
:code:`srun` often works when :code:`mpirun` doesn’t, so try that.

Communication between ranks on the same node fails
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

OpenMPI has many ways to transfer messages between ranks. If the ranks are on
the same node, it is faster to do these transfers using shared memory rather
than involving the network stack. There are two ways to use shared memory.

The first and older method is to use POSIX or SysV shared memory segments.
This approach uses two copies: one from Rank A to shared memory, and a second
from shared memory to Rank B. For example, the :code:`sm` *byte transport
layer* (BTL) does this.

The second and newer method is to use the :code:`process_vm_readv(2)` and/or
:code:`process_vm_writev(2)`) system calls to transfer messages directly from
Rank A’s virtual memory to Rank B’s. This approach is known as *cross-memory
attach* (CMA). It gives significant performance improvements in `benchmarks
<https://blogs.cisco.com/performance/the-vader-shared-memory-transport-in-open-mpi-now-featuring-3-flavors-of-zero-copy>`_,
though of course the real-world impact depends on the application. For
example, the :code:`vader` BTL (enabled by default in OpenMPI 2.0) and
:code:`psm2` *matching transport layer* (MTL) do this.

The problem in Charliecloud is that the second approach does not work by
default.

We can demonstrate the problem with LAMMPS molecular dynamics application::

  $ srun --cpus-per-task 1 ch-run /var/tmp/lammps_mpi -- \
    lmp_mpi -log none -in /lammps/examples/melt/in.melt
  [cn002:21512] Read -1, expected 6144, errno = 1
  [cn001:23947] Read -1, expected 6144, errno = 1
  [cn002:21517] Read -1, expected 9792, errno = 1
  [... repeat thousands of times ...]

With :code:`strace(1)`, one can isolate the problem to the system call noted
above::

  process_vm_readv(...) = -1 EPERM (Operation not permitted)
  write(33, "[cn001:27673] Read -1, expected 6"..., 48) = 48

The `man page <http://man7.org/linux/man-pages/man2/process_vm_readv.2.html>`_
reveals that these system calls require that the process have permission to
:code:`ptrace(2)` one another, but sibling user namespaces `do not
<http://man7.org/linux/man-pages/man2/ptrace.2.html>`_. (You *can*
:code:`ptrace(2)` into a child namespace, which is why :code:`gdb` doesn’t
require anything special in Charliecloud.)

This problem is not specific to containers; for example, many settings of
kernels with `YAMA
<https://www.kernel.org/doc/Documentation/security/Yama.txt>`_ enabled will
similarly disallow this access.

So what can you do? There are a few options:

* We recommend simply using the :code:`--join` family of arguments to
  :code:`ch-run`. This puts a group of :code:`ch-run` peers in the same
  namespaces; then, the system calls work. See the :ref:`man_ch-run` man page
  for details.

* You can also sometimes turn off single-copy. For example, for :code:`vader`,
  set the MCA variable :code:`btl_vader_single_copy_mechanism` to
  :code:`none`, e.g. with an environment variable::

    $ export OMPI_MCA_btl_vader_single_copy_mechanism=none

  :code:`psm2` does not let you turn off CMA, but it does fall back to
  two-copy if CMA doesn’t work. However, this fallback crashed when we tried
  it.

* The kernel module `XPMEM
  <https://github.com/hjelmn/xpmem/tree/master/kernel>`_ enables a different
  single-copy approach. We have not yet tried this, and the module needs to be
  evaluated for user namespace safety, but it’s quite a bit faster than CMA on
  benchmarks.

.. Images by URL only works in Sphinx 1.6+. Debian Stretch has 1.4.9, so
   remove it for now.
   .. image:: https://media.giphy.com/media/1mNBTj3g4jRCg/giphy.gif
      :alt: Darth Vader bowling a strike with the help of the Force
      :align: center

I get a bunch of independent rank-0 processes when launching with :code:`srun`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

For example, you might be seeing this::

  $ srun ch-run /var/tmp/mpihello -- /hello/hello
  0: init ok cn036.localdomain, 1 ranks, userns 4026554634
  0: send/receive ok
  0: finalize ok
  0: init ok cn035.localdomain, 1 ranks, userns 4026554634
  0: send/receive ok
  0: finalize ok

We were expecting a two-rank MPI job, but instead we got two independent
one-rank jobs that did not coordinate.

MPI ranks start as normal, independent processes that must find one another
somehow in order to sync up and begin the coupled parallel program; this
happens in :code:`MPI_Init()`.

There are lots of ways to do this coordination. Because we are launching with
the host's Slurm, we need it to provide something for the containerized
processes for such coordination. OpenMPI must be compiled to use what that
Slurm has to offer, and Slurm must be told to offer it. What works for us is a
something called "PMI2". You can see if your Slurm supports it with::

  $ srun --mpi=list
  srun: MPI types are...
  srun: mpi/pmi2
  srun: mpi/openmpi
  srun: mpi/mpich1_shmem
  srun: mpi/mpich1_p4
  srun: mpi/lam
  srun: mpi/none
  srun: mpi/mvapich
  srun: mpi/mpichmx
  srun: mpi/mpichgm

If :code:`pmi2` is not in the list, you must ask your admins to enable Slurm's
PMI2 support. If it is in the list, but you're seeing this problem, that means
it is not the default, and you need to tell Slurm you want it. Try::

  $ export SLURM_MPI_TYPE=pmi2
  $ srun ch-run /var/tmp/mpihello -- /hello/hello
  0: init ok wc035.localdomain, 2 ranks, userns 4026554634
  1: init ok wc036.localdomain, 2 ranks, userns 4026554634
  0: send/receive ok
  0: finalize ok

How do I run X11 apps?
----------------------

X11 applications should “just work”. For example, try this Dockerfile:

.. code-block:: docker

  FROM debian:stretch
  RUN    apt-get update \
      && apt-get install -y xterm

Build it and unpack it to :code:`/var/tmp`. Then::

  $ ch-run /scratch/ch/xterm -- xterm

should pop an xterm.

If your X11 application doesn’t work, please file an issue so we can
figure out why.
