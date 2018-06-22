Frequently asked questions (FAQ)
********************************

.. contents::
   :depth: 2
   :local:


Where did the name Charliecloud come from?
==========================================

*Charlie* — Charles F. McMillan was director of Los Alamos National Laboratory
from June 2011 until December 2017, i.e., at the time Charliecloud was started
in early 2014. He is universally referred to as "Charlie" here.

*cloud* — Charliecloud provides cloud-like flexibility for HPC systems.

How do you spell Charliecloud?
==============================

We try to be consistent with *Charliecloud* — one word, no camel case. That
is, *Charlie Cloud* and *CharlieCloud* are both incorrect.

My app needs to write to :code:`/var/log`, :code:`/run`, etc.
=============================================================

Because the image is mounted read-only by default, log files, caches, and
other stuff cannot be written anywhere in the image. You have three options:

1. Configure the application to use a different directory. :code:`/tmp` is
   often a good choice, because it's shared with the host and fast.

2. Use :code:`RUN` commands in your Dockerfile to create symlinks that point
   somewhere writeable, e.g. :code:`/tmp`, or :code:`/mnt/0` with
   :code:`ch-run --bind`.

3. Run the image read-write with :code:`ch-run -w`. Be careful that multiple
   containers do not try to write to the same image files.


Tarball build fails with "No command specified"
===============================================

The full error from :code:`ch-docker2tar` or :code:`ch-build2dir` is::

  docker: Error response from daemon: No command specified.

You will also see it with various plain Docker commands.

This happens when there is no default command specified in the Dockerfile or
any of its ancestors. Some base images specify one (e.g., Debian) and others
don't (e.g., Alpine). Docker requires this even for commands that don't seem
like they should need it, such as :code:`docker create` (which is what trips
up Charliecloud).

The solution is to add a default command to your Dockerfile, such as
:code:`CMD ["true"]`.


:code:`--uid 0` lets me read files I can't otherwise!
=====================================================

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

At first glance, it seems that we've found an escalation -- we were able to
read a file inside a container that we could not read on the host! That seems
bad.

However, what is really going on here is more prosaic but complicated:

1. After :code:`unshare(CLONE_NEWUSER)`, :code:`ch-run` gains all capabilities
   inside the namespace. (Outside, capabilities are unchanged.)

2. This include :code:`CAP_DAC_OVERRIDE`, which enables a process to
   read/write/execute a file or directory mostly regardless of its permission
   bits. (This is why root isn't limited by permissions.)

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

This isn't a problem. The quirk applies only to files owned by the invoking
user, because :code:`ch-run` is unprivileged outside the namespace, and thus
he or she could simply :code:`chmod` the file to read it. Access inside and
outside the container remains equivalent.

References:

* http://man7.org/linux/man-pages/man7/capabilities.7.html
* http://lxr.free-electrons.com/source/kernel/capability.c?v=4.2#L442
* http://lxr.free-electrons.com/source/fs/namei.c?v=4.2#L328


Why is :code:`/bin` being added to my :code:`$PATH`?
====================================================

Newer Linux distributions replace some root-level directories, such as
:code:`/bin`, with symlinks to their counterparts in :code:`/usr`.

Some of these distributions (e.g., Fedora 24) have also dropped :code:`/bin`
from the default :code:`$PATH`. This is a problem when the guest OS does *not*
have a merged :code:`/usr` (e.g., Debian 8 "Jessie").

While Charliecloud's general philosophy is not to manipulate environment
variables, in this case, guests can be severely broken if :code:`/bin` is not
in :code:`$PATH`. Thus, we add it if it's not there.

Further reading:

  * `The case for the /usr Merge <https://www.freedesktop.org/wiki/Software/systemd/TheCaseForTheUsrMerge/>`_
  * `Fedora <https://fedoraproject.org/wiki/Features/UsrMove>`_
  * `Debian <https://wiki.debian.org/UsrMerge>`_


:code:`ch-run` fails with "can't re-mount image read-only"
==========================================================

Normally, :code:`ch-run` re-mounts the image directory read-only within the
container. This fails if the image resides on certain filesystems, such as NFS
(see `issue #9 <https://github.com/hpc/charliecloud/issues/9>`_). There are
two solutions:

1. Unpack the image into a different filesystem, such as :code:`tmpfs` or
   local disk. Consult your local admins for a recommendation. Note that
   :code:`tmpfs` is a lot faster than Lustre.

2. Use the :code:`-w` switch to leave the image mounted read-write. Note that
   this has may have an impact on reproducibility (because the application can
   change the image between runs) and/or stability (if there are multiple
   application processes and one writes a file in the image that another is
   reading or writing).


Which specific :code:`sudo` commands are needed?
================================================

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


OpenMPI Charliecloud jobs don't work
=====================================

MPI can be finicky. This section documents some of the problems we've seen.

:code:`mpirun` can't launch jobs
--------------------------------

For example, you might see::

  $ mpirun -np 1 ch-run /var/tmp/mpihello -- /hello/hello
  App launch reported: 2 (out of 2) daemons - 0 (out of 1) procs
  [cn001:27101] PMIX ERROR: BAD-PARAM in file src/dstore/pmix_esh.c at line 996

We're not yet sure why this happens — it may be a mismatch between the OpenMPI
builds inside and outside the container — but in our experience launching with
:code:`srun` often works when :code:`mpirun` doesn't, so try that.

My ranks can't talk to one another and I'm told Darth Vader has something to do with it
---------------------------------------------------------------------------------------

OpenMPI has the notion of a *byte transport layer* (BTL), which is a module
that defines how messages are passed from one rank to another. There are many
different BTLs.

One is called :code:`vader`, and in OpenMPI 2.0 it enabled single-copy data
transfers between ranks on the same node. Previously by default, and in the
older :code:`sm` BTL, such messages had to be copied once into shared memory
and a second time into the destination process. Single-copy enables the
message to be copied directly from one rank to another. This gives significant
performance improvements in `benchmarks
<https://blogs.cisco.com/performance/the-vader-shared-memory-transport-in-open-mpi-now-featuring-3-flavors-of-zero-copy>`_,
though of course the real-world impact depends on the application.

One manifestation of this is in the LAMMPS molecular dynamics application::

  $ srun --cpus-per-task 1 ch-run /var/tmp/lammps_mpi -- \
    lmp_mpi -log none -in /lammps/examples/melt/in.melt
  [cn002:21512] Read -1, expected 6144, errno = 1
  [cn001:23947] Read -1, expected 6144, errno = 1
  [cn002:21517] Read -1, expected 9792, errno = 1
  [... repeat thousands of times ...]

With :code:`strace`, one can isolate the problem to the system call
:code:`process_vm_readv(2)` (and perhaps also :code:`process_vm_writev(2)`)::

  process_vm_readv(...) = -1 EPERM (Operation not permitted)
  write(33, "[cn001:27673] Read -1, expected 6"..., 48) = 48

The `man page <http://man7.org/linux/man-pages/man2/process_vm_readv.2.html>`_
reveals that these system calls require that the process have permission to
:code:`ptrace(2)` one another, but sibling user namespaces `do not
<http://man7.org/linux/man-pages/man2/ptrace.2.html>`_. (You *can*
:code:`ptrace(2)` into a child namespace, which is why :code:`gdb` doesn't
require anything special in Charliecloud.)

This problem is not specific to containers; for example, many settings of
kernels with `YAMA
<https://www.kernel.org/doc/Documentation/security/Yama.txt>`_ enabled will
similarly disallow this access.

Thus, :code:`vader` CMA does not currently work in Charliecloud by default. So
what can you do?

* The easiest thing is to simply turn off single-copy. For most applications,
  we suspect the performance impact will be minimal, but you should of course
  evaluate that yourself. To do so, either set an environment variable::

    export OMPI_MCA_btl_vader_single_copy_mechanism=none

  or add an argument to :code:`mpirun`::

    $ mpirun --mca btl_vader_single_copy_mechanism none ...

* The kernel module `XPMEM
  <https://github.com/hjelmn/xpmem/tree/master/kernel>`_ enables a different
  single-copy approach. We have not yet tried this, and the module needs to be
  evaluated for user namespace safety, but it's quite a bit faster than CMA on
  benchmarks.

* Wait. We are in communication with the OpenMPI developers on this, and they
  may implement a fallback mechanism to keep your application working rather
  than failing. This would, however, have the same performance impact as the
  first approach.

* Heroics. With sufficient shell voodoo, one could get all the ranks into the
  same user namespace, at which point the problem goes away.

We are tracking this problem in `issue #128
<https://github.com/hpc/charliecloud/issues/128>`_. It is possible that we can
do something in Charliecloud to make it work, but we don't know yet.

.. Images by URL only works in Sphinx 1.6+. Debian Stretch has 1.4.9, so
   remove it for now.
   .. image:: https://media.giphy.com/media/1mNBTj3g4jRCg/giphy.gif
      :alt: Darth Vader bowling a strike with the help of the Force
      :align: center

How do I run X11 apps?
======================

X11 applications should "just work". For example, try this Dockerfile:

.. code-block:: docker

  FROM debian:stretch
  RUN    apt-get update \
      && apt-get install -y xterm

Build it and unpack it to :code:`/var/tmp`. Then::

  $ ch-run /scratch/ch/xterm -- xterm

should pop an xterm.

If your X11 application doesn't work, please file an issue so we can
figure out why.

Why does :code:`ping` not work?
===============================

:code:`ping` fails with "permission denied" under Charliecloud, even if you're
UID 0 inside the container::

  $ ch-run $IMG -- ping 8.8.8.8
  PING 8.8.8.8 (8.8.8.8): 56 data bytes
  ping: permission denied (are you root?)
  $ ch-run --uid=0 $IMG -- ping 8.8.8.8
  PING 8.8.8.8 (8.8.8.8): 56 data bytes
  ping: permission denied (are you root?)

This is because :code:`ping` needs a raw socket to construct the needed
:code:`ICMP ECHO` packets, which requires capability :code:`CAP_NET_RAW` or
root. Unprivileged users can normally use :code:`ping` because it's a setuid
or setcap binary: it raises privilege using the filesystem bits on the
executable to obtain a raw socket.

Under Charliecloud, there are multiple reasons :code:`ping` can't get a raw
socket. First, images are unpacked without privilege, meaning that setuid and
setcap bits are lost. But even if you do get privilege in the container (e.g.,
with :code:`--uid=0`), this only applies in the container. Charliecloud uses
the host's network namespace, where your unprivileged host identity applies
and :code:`ping` still can't get a raw socket.

The recommended alternative is to simply try the thing you want to do, without
testing connectivity using :code:`ping` first.
