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

How large is Charliecloud?
--------------------------

.. include:: loc.rst


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

:code:`ch-image` fails with "certificate verify failed"
-------------------------------------------------------

When :code:`ch-image` interacts with a remote registry (e.g., via :code:`push`
or :code:`pull` subcommands), it will verify the registry's HTTPS certificate.
If this fails, :code:`ch-image` will exit with the error "certificate verify
failed".

This situation tends to arise with self-signed or institutionally-signed
certificates, even if the OS is configured to trust them. We use the Python
HTTP library Requests, which on many platforms `includes its own CA
certificates bundle
<https://docs.python-requests.org/en/master/user/advanced/#ca-certificates>`_,
ignoring the bundle installed by the OS.

Requests can be directed to use an alternate bundle of trusted CAs by setting
environment variable :code:`REQUESTS_CA_BUNDLE` to the bundle path. (See `the
Requests documentation
<https://docs.python-requests.org/en/master/user/advanced/#ssl-cert-verification>`_
for details.) For example::

  $ export REQUESTS_CA_BUNDLE=/usr/local/share/ca-certificates/registry.crt
  $ ch-image pull registry.example.com/image:tag

Alternatively, certificate verification can be disabled entirely with the
:code:`--tls-no-verify` flag. However, users should enable this option only if
they have other means to be confident in the registry's identity.

"storage directory seems invalid"
---------------------------------

Charliecloud uses its *storage directory* (:code:`/var/tmp/$USER.sh` by
default) for various internal uses. As such, Charliecloud needs complete
control over this directory's contents. This error happens when the storage
directory exists but its contents do not match what's expected, including if
it's an empty directory, which is to protect against using common temporary
directories like :code:`/tmp` or :code:`/var/tmp` as the storage directory.

Let Charliecloud create the storage directory. For example, if you want to use
:code:`/big/containers/$USER/charlie` for the storage directory (e.g., by
setting :code:`CH_IMAGE_STORAGE`), ensure :code:`/big/containers/$USER` exists
but do not create the final directory :code:`charlie`.


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

  * :code:`0.2.1~pre+1a99f42` : Master branch commit 1a99f42, built from a
    clean working directory (i.e., no changes since that commit).

  * :code:`0.2.1~pre+foo1.0729a78` : Commit 0729a78 on branch :code:`foo-1`,
    :code:`foo_1`, etc. built from clean working directory.

  * :code:`0.2.1~pre+foo1.0729a78.dirty` : Commit 0729a78 on one of those
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

:code:`ch-convert` from Docker incorrect image sizes
----------------------------------------------------

When converting from Docker, :code:`ch-convert` often finishes before the
progress bar is complete. For example::

  $ ch-convert -i docker foo /var/tmp/foo.tar.gz
  input:   docker    foo
  output:  tar       /var/tmp/foo.tar.gz
  exporting ...
   373MiB 0:00:21 [============================>                 ] 65%
  [...]

In this case, the :code:`.tar.gz` contains 392 MB uncompressed::

  $ zcat /var/tmp/foo.tar.gz | wc
  2740966 14631550 392145408

But Docker thinks the image is 597 MB::

  $ sudo docker image inspect foo | fgrep -i size
          "Size": 596952928,
          "VirtualSize": 596952928,

We've also seen cases where the Docker-reported size is an *under*\ estimate::

  $ ch-convert -i docker bar /var/tmp/bar.tar.gz
  input:   docker    bar
  output:  tar       /var/tmp/bar.tar.gz
  exporting ...
   423MiB 0:00:22 [============================================>] 102%
  [...]
  $ zcat /var/tmp/bar.tar.gz | wc
  4181186 20317858 444212736
  $ sudo docker image inspect bar | fgrep -i size
          "Size": 433812403,
          "VirtualSize": 433812403,

We think that this is because Docker is computing size based on the size of
the layers rather than the unpacked image. We do not currently have a fix; see
`issue #165 <https://github.com/hpc/charliecloud/issues/165>`_.

My password that contains digits doesn't work in VirtualBox console
-------------------------------------------------------------------

VirtualBox has confusing Num Lock behavior. Thus, you may be typing arrows,
page up/down, etc. instead of digits, without noticing because console
password fields give no feedback, not even whether a character has been typed.

Try using the number row instead, toggling Num Lock key, or SSHing into the
virtual machine.

Mode bits (permission bits) are lost
------------------------------------

Charliecloud preserves only some mode bits, specifically user, group, and
world permissions, and the `restricted deletion flag
<https://man7.org/linux/man-pages/man1/chmod.1.html#RESTRICTED_DELETION_FLAG_OR_STICKY_BIT>`_
on directories; i.e. 777 on files and 1777 on directories.

The setuid (4000) and setgid (2000) bits are not preserved because ownership
of files within Charliecloud images is that of the user who unpacks the image.
Leaving these bits set could therefore surprise that user by unexpectedly
creating files and directories setuid/gid to them.

The sticky bit (1000) is not preserved for files because :code:`unsquashfs(1)`
unsets it even with umask 000. However, this is bit is largely obsolete for
files.

Note the non-preserved bits may *sometimes* be retained, but this is undefined
behavior. The specified behavior is that they may be zeroed at any time.


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

  $ mpirun -np 1 ch-run /var/tmp/mpihello-openmpi -- /hello/hello
  App launch reported: 2 (out of 2) daemons - 0 (out of 1) procs
  [cn001:27101] PMIX ERROR: BAD-PARAM in file src/dstore/pmix_esh.c at line 996

We’re not yet sure why this happens — it may be a mismatch between the OpenMPI
builds inside and outside the container — but in our experience launching with
:code:`srun` often works when :code:`mpirun` doesn’t, so try that.

.. _faq_join:

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

  $ srun ch-run /var/tmp/mpihello-openmpi -- /hello/hello
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
  $ srun ch-run /var/tmp/mpihello-openmpi -- /hello/hello
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

How do I specify an image reference?
------------------------------------

You must specify an image for many use cases, including :code:`FROM`
instructions, the source of an image pull (e.g. :code:`ch-image pull` or
:code:`docker pull`), the destination of an image push, and adding image tags.
Charliecloud calls this an *image reference*, but there appears to be no
established name for this concept.

The syntax of an image reference is not well documented. This FAQ represents
our understanding, which is cobbled together from the `Dockerfile reference
<https://docs.docker.com/engine/reference/builder/#from>`_, the :code:`docker
tag` `documentation
<https://docs.docker.com/engine/reference/commandline/tag/>`_, and various
forum posts. It is not a precise match for how Docker implements it, but it
should be close enough.

We'll start with two complete examples with all the bells and whistles:

1. :code:`example.com:8080/foo/bar/hello-world:version1.0`
2. :code:`example.com:8080/foo/bar/hello-world@sha256:f6c68e2ad82a`

These references parse into the following components, in this order:

1. A `valid hostname <https://en.wikipedia.org/wiki/Hostname>`_; we assume
   this matches the regular expression :code:`[A-Za-z0-9.-]+`, which is very
   approximate. Optional; here :code:`example.com`.

2. A colon followed by a decimal port number. If hostname is given, optional;
   otherwise disallowed; here :code:`8080`.

3. If hostname given, a slash.

4. A path, with one or more components separated by slash. Components match
   the regex :code:`[a-z0-9_.-]+`. Optional; here :code:`foo/bar`. Pedantic
   details:

   * Under the hood, the default path is :code:`library`, but this is
     generally not exposed to users.

   * Three or more underscores in a row is disallowed by Docker, but we don't
     check this.

5. If path given, a slash.

6. The image name (tag), which matches :code:`[a-z0-9_.-]+`. Required; here
   :code:`hello-world`.

7. Zero or one of:

   * A tag matching the regular expression :code:`[A-Za-z0-9_.-]+` and
     preceded by a colon. Here :code:`version1.0` (example 1).

   * A hexadecimal hash preceded by the string :code:`@sha256:`. Here
     :code:`f6c68e2ad82a` (example 2).

     * Note: Digest algorithms other than SHA-256 are in principle allowed,
       but we have not yet seen any.

Detail-oriented readers may have noticed the following gotchas:

* A hostname without port number is ambiguous with the leading component of a
  path. For example, in the reference :code:`foo/bar/baz`, it is ambiguous
  whether :code:`foo` is a hostname or the first (and only) component of the
  path :code:`foo/bar`. The `resolution rule
  <https://stackoverflow.com/a/37867949>`_ is: if the ambiguous substring
  contains a dot, assume it's a hostname; otherwise, assume it's a path
  component.

* The only character than cannot go in a POSIX filename is slash. Thus,
  Charliecloud uses image references in filenames, replacing slash with
  percent (:code:`%`). Because this character cannot appear in image
  references, the transformation is reversible.

  An alternate approach would be to replicate the reference path in the
  filesystem, i.e., path components in the reference would correspond directly
  to a filesystem path. This would yield a clearer filesystem structure.
  However, we elected not to do it because it complicates the code to save and
  clean up image reference-related data, and it does not address a few related
  questions, e.g. should the host and port also be a directory level.

Usually, most of the components are omitted. For example, you'll more commonly
see image references like:

  * :code:`debian`, which refers to the tag :code:`latest` of image
    :code:`debian` from Docker Hub.
  * :code:`debian:stretch`, which is the same except for tag :code:`stretch`.
  * :code:`fedora/httpd`, which is tag :code:`latest` of :code:`fedora/httpd`
    from Docker Hub.

See :code:`charliecloud.py` for a specific grammar that implements this.

Can I build or pull images using a tool Charliecloud doesn't know about?
------------------------------------------------------------------------

Yes. Charliecloud deals in well-known UNIX formats like directories, tarballs,
and SquashFS images. So, once you get your image into some format Charliecloud
likes, you can enter the workflow.

For example, `skopeo <https://github.com/containers/skopeo>`_ is a tool to
pull images to OCI format, and `umoci <https://umo.ci>`_ can flatten an OCI
image to a directory. Thus, you can use the following commands to run an
Alpine 3.9 image pulled from Docker hub::

  $ skopeo copy docker://alpine:3.9 oci:/tmp/oci:img
  [...]
  $ ls /tmp/oci
  blobs  index.json  oci-layout
  $ umoci unpack --rootless --image /tmp/oci:img /tmp/alpine:3.9
  [...]
  $ ls /tmp/alpine:3.9
  config.json
  rootfs
  sha256_2ca27acab3a0f4057852d9a8b775791ad8ff62fbedfc99529754549d33965941.mtree
  umoci.json
  $ ls /tmp/alpine:3.9/rootfs
  bin  etc   lib    mnt  proc  run   srv  tmp  var
  dev  home  media  opt  root  sbin  sys  usr
  $ ch-run /tmp/alpine:3.9/rootfs -- cat /etc/alpine-release
  3.9.5

How do I authenticate with SSH during :code:`ch-image` build?
-------------------------------------------------------------

The simplest approach is to run the `SSH agent
<https://man.openbsd.org/ssh-agent>`_ on the host. :code:`ch-image` then
leverages this with two steps:

  1. pass environment variable :code:`SSH_AUTH_SOCK` into the build, with no
     need to put :code:`ARG` in the Dockerfile or specify :code:`--build-arg`
     on the command line; and

  2. bind-mount host :code:`/tmp` to guest :code:`/tmp`, which is where the
     SSH agent's listening socket usually resides.

Thus, SSH within the container will use this existing SSH agent on the host to
authenticate without further intervention.

For example, after making :code:`ssh-agent` available on the host, which is OS
and site-specific::

  $ echo $SSH_AUTH_SOCK
  /tmp/ssh-rHsFFqwwqh/agent.49041
  $ ssh-add
  Enter passphrase for /home/charlie/.ssh/id_rsa:
  Identity added: /home/charlie/.ssh/id_rsa (/home/charlie/.ssh/id_rsa)
  $ ssh-add -l
  4096 SHA256:aN4n2JeMah2ekwhyHnb0Ug9bYMASmY+5uGg6MrieaQ /home/charlie/.ssh/id_rsa (RSA)
  $ cat ./Dockerfile
  FROM alpine:latest
  RUN apk add openssh
  RUN echo $SSH_AUTH_SOCK
  RUN ssh git@github.com
  $ ch-image build -t foo -f ./Dockerfile .
  [...]
    3 RUN ['/bin/sh', '-c', 'echo $SSH_AUTH_SOCK']
    /tmp/ssh-rHsFFqwwqh/agent.49041
    4 RUN ['/bin/sh', '-c', 'ssh git@github.com']
  [...]
  Hi charlie! You've successfully authenticated, but GitHub does not provide shell access.

Note this example is rather contrived — bare SSH sessions in a Dockerfile
rarely make sense. In practice, SSH is used as a transport to fetch something,
e.g. with :code:`scp(1)` or :code:`git(1)`. See the next entry for a more
realistic example.

SSH stops :code:`ch-image` build with interactive queries
---------------------------------------------------------

This often occurs during an SSH-based Git clone. For example:

.. code-block:: docker

  FROM alpine:latest
  RUN apk add git openssh
  RUN git clone git@github.com:hpc/charliecloud.git

.. code-block:: console

  $ ch-image build -t foo -f ./Dockerfile .
  [...]
  3 RUN ['/bin/sh', '-c', 'git clone git@github.com:hpc/charliecloud.git']
  Cloning into 'charliecloud'...
  The authenticity of host 'github.com (140.82.113.3)' can't be established.
  RSA key fingerprint is SHA256:nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8.
  Are you sure you want to continue connecting (yes/no/[fingerprint])?

At this point, the build stops while SSH waits for input.

This happens even if you have :code:`github.com` in your
:code:`~/.ssh/known_hosts`. This file is not available to the build because
:code:`ch-image` runs :code:`ch-run` with :code:`--no-home`, so :code:`RUN`
instructions can't see anything in your home directory.

Solutions include:

  1. Change to anonymous HTTPS clone, if available. Most public repositories
     will support this. For example:

     .. code-block:: docker

       FROM alpine:latest
       RUN apk add git
       RUN git clone https://github.com/hpc/charliecloud.git

  2. Approve the connection interactively by typing :code:`yes`. Note this
     will record details of the connection within the image, including IP
     address and the fingerprint. The build also remains interactive.

  3. Edit the image's system `SSH config
     <https://man.openbsd.org/ssh_config>`_ to turn off host key checking.
     Note this can be rather hairy, because the SSH config language is quite
     flexible and the first instance of a directive is the one used. However,
     often the changes can be simply appended:

     .. code-block:: docker

       FROM alpine:latest
       RUN apk add git openssh
       RUN printf 'StrictHostKeyChecking=no\nUserKnownHostsFile=/dev/null\n' \
           >> /etc/ssh/ssh_config
       RUN git clone git@github.com:hpc/charliecloud.git

     Check your institutional policy on whether this is permissible, though
     it's worth noting that users `almost never
     <https://www.usenix.org/system/files/login/articles/105484-Gutmann.pdf>`_
     verify the host fingerprints anyway.

     This will not record details of the connection in the image.

  4. Turn off host key checking on the SSH command line. (See caveats in the
     previous item.) The wrapping tool should provide a way to configure this
     command line. For example, for Git:

     .. code-block:: docker

       FROM alpine:latest
       RUN apk add git openssh
       ARG GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
       RUN git clone git@github.com:hpc/charliecloud.git

  5. Add the remote host to the system known hosts file, e.g.:

     .. code-block:: docker

       FROM alpine:latest
       RUN apk add git openssh
       RUN echo 'github.com,140.82.112.4 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==' >> /etc/ssh/ssh_known_hosts
       RUN git clone git@github.com:hpc/charliecloud.git

     This records connection details in both the Dockerfile and the image.

Other approaches could be found with web searches such as "automate unattended
SSH" or "SSH in cron jobs".

.. _faq_building-with-docker:

How do I use Docker to build Charliecloud images?
-------------------------------------------------

The short version is to run Docker commands like :code:`docker build` and
:code:`docker pull` like usual, and then use :code:`ch-convert` to copy the
image from Docker storage to a SquashFS archive, tarball, or directory. If you
are behind an HTTP proxy, that requires some extra setup for Docker; see
below.

Security implications of Docker
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Because Docker (a) makes installing random crap from the internet simple and
(b) is easy to deploy insecurely, you should take care. Some of the
implications are below. This list should not be considered comprehensive nor a
substitute for appropriate expertise; adhere to your ethical and institutional
responsibilities.

* **Docker equals root.** Anyone who can run the :code:`docker` command or
  interact with the Docker daemon can `trivially escalate to root
  <http://web.archive.org/web/20170614013206/http://www.reventlov.com/advisories/using-the-docker-command-to-root-the-host>`_.
  This is considered a feature.

  For this reason, don't create the :code:`docker` group, as this will allow
  passwordless, unlogged escalation for anyone in the group. Run it with
  :code:`sudo docker`.

  Also, Docker runs container processes as root by default. In addition to
  being poor hygiene, this can be an escalation path, e.g. if you bind-mount
  host directories.

* **Docker alters your network configuration.** To see what it did::

    $ ifconfig    # note docker0 interface
    $ brctl show  # note docker0 bridge
    $ route -n

* **Docker installs services.** If you don't want the Docker service starting
  automatically at boot, e.g.::

    $ systemctl is-enabled docker
    enabled
    $ systemctl disable docker
    $ systemctl is-enabled docker
    disabled

Configuring for a proxy
~~~~~~~~~~~~~~~~~~~~~~~

By default, Docker does not work if you are behind a proxy, and it fails in
two different ways.

The first problem is that Docker itself must be told to use a proxy. This
manifests as::

  $ sudo docker run hello-world
  Unable to find image 'hello-world:latest' locally
  Pulling repository hello-world
  Get https://index.docker.io/v1/repositories/library/hello-world/images: dial tcp 54.152.161.54:443: connection refused

If you have a systemd system, the `Docker documentation
<https://docs.docker.com/engine/admin/systemd/#http-proxy>`_ explains how to
configure this. If you don't have a systemd system, then
:code:`/etc/default/docker` might be the place to go?

The second problem is that programs executed during build (:code:`RUN`
instructions) need to know about the proxy as well. This manifests as images
failing to build because they can't download stuff from the internet.

One fix is to configure your :code:`.bashrc` or equivalent to:

1. Set the proxy environment variables:

   .. code-block:: sh

     export HTTP_PROXY=http://proxy.example.com:8088
     export http_proxy=$HTTP_PROXY
     export HTTPS_PROXY=$HTTP_PROXY
     export https_proxy=$HTTP_PROXY
     export NO_PROXY='localhost,127.0.0.1,.example.com'
     export no_proxy=$NO_PROXY

2. Configure a :code:`docker build` wrapper:

   .. code-block:: sh

     # Run "docker build" with specified arguments, adding proxy variables if
     # set. Assumes "sudo" is needed to run "docker".
     function docker-build () {
         if [[ -z $HTTP_PROXY ]]; then
             sudo docker build "$@"
         else
             sudo docker build --build-arg HTTP_PROXY="$HTTP_PROXY" \
                               --build-arg HTTPS_PROXY="$HTTPS_PROXY" \
                               --build-arg NO_PROXY="$NO_PROXY" \
                               --build-arg http_proxy="$http_proxy" \
                               --build-arg https_proxy="$https_proxy" \
                               --build-arg no_proxy="$no_proxy" \
                               "$@"
         fi
     }


How can I build images for a foreign architecture?
--------------------------------------------------

QEMU
~~~~

Suppose you want to build Charliecloud containers on a system which has a
different architecture from the target system.

It's straightforward as long as you can install suitable packages on the build
system (your personal computer?). You just need the magic of QEMU via a
distribution package with a name like Debian's :code:`qemu-user-static`. For
use in an image root this needs to be the :code:`-static` version, not plain
:code:`qemu-user`, and contain a :code:`qemu-*-static` executable for your
target architecture. In case it doesn't install “binfmt” hooks (telling Linux
how to run foreign binaries), you'll need to make that work — perhaps it's in
another package.

That's all you need to make building with :code:`ch-image` work with a base
foreign architecture image and the :code:`--arch` option. It's significantly
slower than native, but quite usable — about half the speed of native for the
ppc64le target with a build taking minutes on a laptop with a magnetic disc.
There's a catch that images in :code:`ch-image` storage aren't distinguished
by architecture except by any name you give them, e.g., a base image like
:code:`debian:11` pulled with :code:`--arch ppc64le` will overwrite a native
x86 one.

For example, to build a ppc64le image on a Debian Buster amd64 host::

  $ uname -m
  x86_64
  $ sudo apt install qemu-user-static
  $ ch-image pull --arch ppc64le alpine:3.15
  $ printf 'FROM alpine:3.15\nRUN apk add coreutils\n' | ch-image build -t foo -
  $ ch-convert alpine:3.15 /var/tmp/foo
  $ ch-run /var/tmp/foo -- uname -m
  ppc64le

PRoot
~~~~~

Another way to build a foreign image, which works even without :code:`sudo` to
install :code:`qemu-*-static`, is to populate a chroot for it with the `PRoot
<https://proot-me.github.io/>`_ tool, whose :code:`-q` option allows
specifying a :code:`qemu-*-static` binary (perhaps obtained by unpacking a
distribution package).


How can I use tarball base images from e.g. linuxcontainers.org?
----------------------------------------------------------------

If you can't find an image repository from which to pull for the distribution
and architecture of interest, it is worth looking at the extensive collection
of rootfs archives `maintained by linuxcontainers.org
<https://uk.lxd.images.canonical.com/images/>`_. They are meant for LXC, but
are fine as a basis for Charliecloud.

For example, this would leave a :code:`ppc64le/alpine:3.15` image du jour in
the registry for use in a Dockerfile :code:`FROM` line. Note that
linuxcontainers.org uses the opposite order for “le” in the architecture name.

::

  $ wget https://uk.lxd.images.canonical.com/images/alpine/3.15/ppc64el/default/20220304_13:00/rootfs.tar.xz
  $ ch-image import rootfs.tar.xz ppc64le/alpine:3.15


..  LocalWords:  CAs SY Gutmann AUTH rHsFFqwwqh MrieaQ Za loc mpihello mvo du
..  LocalWords:  VirtualSize linuxcontainers jour uk lxd
