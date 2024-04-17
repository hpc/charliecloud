Best practices
**************

.. contents::
   :depth: 3
   :local:

Other best practices information
================================

This isn’t the last word. Also consider:

* Many of Docker’s `Best practices for writing Dockerfiles
  <https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices>`_
  apply to Charliecloud images as well.

* “`Recommendations for the packaging and containerizing of bioinformatics
  software <https://f1000research.com/articles/7-742/v2>`_”, Gruening et al.
  2019, is a thoughtful editorial with eleven specific containerization
  recommendations for scientific software.

* “`Application container security guide
  <https://nvlpubs.nist.gov/nistpubs/specialpublications/nist.sp.800-190.pdf>`_”,
  NIST Special Publication 800-190; Souppaya, Morello, and Scarfone 2017.


Filesystems
===========

There are two performance gotchas to be aware of for Charliecloud.

Metadata traffic
----------------

Directory-format container images and the Charliecloud storage directory often
contain, and thus Charliecloud must manipulate, a very large number of files.
For example, after running the test suite, the storage directory contains
almost 140,000 files. That is, metadata traffic can be quite high.

Such images and the storage directory should be stored on a filesystem with
reasonable metadata performance. Notably, this *excludes* Lustre, which is
commonly used for scratch filesystems in HPC; i.e., don’t store these things
on Lustre. NFS is usually fine, though in general it performs worse than a
local filesystem.

In contrast, SquashFS images, which encapsulate the image into a single file
that is mounted using FUSE at runtime, insulate the filesystem from this
metadata traffic. Images in this format are suitable for any filesystem,
including Lustre.

.. _best-practices_file-copy:

File copy performance
---------------------

:code:`ch-image` does a lot of file copying. The bulk of this is manipulating
images in the storage directory. Importantly, this includes :ref:`large files
<ch-image_bu-large>` stored by the build cache outside its Git repository,
though this feature is disabled by default.

Copies are costly both in time (to read, transfer, and write the duplicate
bytes) and space (to store the bytes). However significant optimizations are
sometimes available. Charliecloud’s internal file copies (unfortunately not
sub-programs like Git) can take advantage of multiple optimized file-copy
paths offered by Linux:

in-kernel copy
   Copy data inside the kernel without passing through user-space. Saves time
   but not space.

server-side copy
   Copy data on the server without sending it over the network, relevant only
   for network filesystems. Saves time but not space.

reflink copy (best)
   Copy-on-write via “`reflink
   <https://blog.ram.rachum.com/post/620335081764077568/symlinks-and-hardlinks-move-over-make-room-for>`_”.
   The destination file gets a new inode but shares the data extents of the
   source file — i.e., no data are copied! — with extents unshared later
   if/when are written. Saves both time and space (and potentially quite a
   lot).

To use these optimizations, you need:

   1. Python ≥3.8, for :code:`os.copy_file_range()` (`docs
      <https://docs.python.org/3/library/os.html#os.copy_file_range>`_), which
      wraps :code:`copy_file_range(2)` (`man page
      <https://man7.org/linux/man-pages/man2/copy_file_range.2.html>`_), which
      selects the best method from the three above.

   2. A new-ish Linux kernel (details vary).

   3. The right filesystem.

.. |yes| replace:: ✅
.. |no| replace:: ❌

The following table summarizes our (possibly incorrect) understanding of
filesystem support as of October 2023. For current or historical information,
see the `Linux source code
<https://elixir.bootlin.com/linux/latest/A/ident/remap_file_range>`_ for
in-kernel filesystems or specific filesystem release nodes, e.g. `ZFS
<https://github.com/openzfs/zfs/releases>`_. A checkmark |yes| indicates
supported, |no| unsupported. We recommend using a filesystem that supports
reflink and also (if applicable) server-side copy.

+----------------------------+---------------+---------------+----------------+
|                            | in-kernel     | server-side   | reflink (best) |
+============================+===============+===============+================+
| *local filesystems*                                                         |
+----------------------------+---------------+---------------+----------------+
| BTRFS                      | |yes|         | n/a           | |yes|          |
+----------------------------+---------------+---------------+----------------+
| OCFS2                      | |yes|         | n/a           | |yes|          |
+----------------------------+---------------+---------------+----------------+
| XFS                        | |yes|         | n/a           | |yes|          |
+----------------------------+---------------+---------------+----------------+
| ZFS                        | |yes|         | n/a           | |yes| [1]      |
+----------------------------+---------------+---------------+----------------+
| *network filesystems*                                                       |
+----------------------------+---------------+---------------+----------------+
| CIFS/SMB                   | |yes|         | |yes|         | ?              |
+----------------------------+---------------+---------------+----------------+
| NFSv3                      | |yes|         | |no|          | |no|           |
+----------------------------+---------------+---------------+----------------+
| NFSv4                      | |yes|         | |yes|         | |yes| [2]      |
+----------------------------+---------------+---------------+----------------+
| *other situations*                                                          |
+----------------------------+---------------+---------------+----------------+
| filesystems not listed     | |yes|         | |no|          | |no|           |
+----------------------------+---------------+---------------+----------------+
| copies between filesystems | |no| [3]      | |no|          | |no|           |
+----------------------------+---------------+---------------+----------------+

Notes:

  1. As of `ZFS 2.2.0
     <https://github.com/openzfs/zfs/releases/tag/zfs-2.2.0>`_.

  2. If the underlying exported filesystem also supports reflink.

  3. Recent kernels (≥5.18 as well as stable kernels if backported) support
     in-kernel file copy between filesystems, but for many kernels it is `not
     stable
     <https://man7.org/linux/man-pages/man2/copy_file_range.2.html#BUGS>`_, so
     Charliecloud does not currently attempt it.

Installing your own software
============================

This section covers four situations for making software available inside a
Charliecloud container:

  1. Third-party software installed into the image using a package manager.
  2. Third-party software compiled from source into the image.
  3. Your software installed into the image.
  4. Your software stored on the host but compiled in the container.

.. note::
   Maybe you don’t have to install the software at all. Is there already a
   trustworthy image on Docker Hub you can use as a base?

Third-party software via package manager
----------------------------------------

This approach is the simplest and fastest way to install stuff in your image.
The :code:`examples/hello` Dockerfile does this to install the package
:code:`openssh-client`:

.. literalinclude:: ../examples/hello/Dockerfile
   :language: docker
   :lines: 3-7

You can use distribution package managers such as :code:`dnf`, as demonstrated
above, or others, such as :code:`pip` for Python packages. Be aware that the
software will be downloaded anew each time you execute the instruction (unless
you add an HTTP cache, which is out of scope of this documentation).

.. note::

   RPM and friends (:code:`yum`, :code:`dnf`, etc.) have traditionally been
   rather troublesome in containers, and we suspect there are bugs we haven’t
   ironed out yet. If you encounter problems, please do file a bug!

Third-party software compiled from source
-----------------------------------------

Under this method, one uses :code:`RUN` commands to fetch the desired software
using :code:`curl` or :code:`wget`, compile it, and install. Our example
(:code:`examples/Dockerfile.almalinux_8ch`) does this with ImageMagick:

.. literalinclude:: ../examples/Dockerfile.almalinux_8ch
   :language: docker
   :lines: 2-

So what is going on here?

#. Use the latest AlmaLinux 8 as the base image.

#. Install some packages using :code:`dnf`, the OS package manager, including
   a basic development environment.

#. Install :code:`wheel` using :code:`pip` and adjust the shared library
   configuration. (These are not needed for ImageMagick but rather support
   derived images.)

#. For ImageMagick itself:

   #. Download and untar. Note the use of the variable :code:`MAGICK_VERSION`
      and versions easier.

   #. Build and install. Note the :code:`getconf` trick to guess at an
      appropriate parallel build.

   #. Clean up, in order to reduce the size of the build cache as well as the
      resulting Charliecloud image (:code:`rm -Rf`).

.. note::

   Because it’s a container image, you can be less tidy than you might
   normally be. For example, we install ImageMagick directly into
   :code:`/usr/local` rather than using something like `GNU Stow
   <https://www.gnu.org/software/stow/>`_ to organize this directory tree.

Your software stored in the image
---------------------------------

This method covers software provided by you that is included in the image.
This is recommended when your software is relatively stable or is not easily
available to users of your image, for example a library rather than simulation
code under active development.

The general approach is the same as installing third-party software from
source, but you use the :code:`COPY` instruction to transfer files from the
host filesystem (rather than the network via HTTP) to the image. For example,
:code:`examples/mpihello/Dockerfile.openmpi` uses this approach:

.. literalinclude:: ../examples/mpihello/Dockerfile.openmpi
  :language: docker

These Dockerfile instructions:

1. Copy the host directory :code:`examples/mpihello` to the image at path
   :code:`/hello`. The host path is relative to the *context directory*, which
   is tarred up and sent to the Docker daemon. Docker builds have no access to
   the host filesystem outside the context directory.

   (Unlike HPC, Docker comes from a world without network filesystems. This
   tar-based approach lets the Docker daemon run on a different node from the
   client without needing any shared filesystems.)

   The usual convention, including for Charliecloud tests and examples, is
   that the context is the directory containing the Dockerfile in question. A
   common pattern, used here, is to copy in the entire context.

2. :code:`cd` to :code:`/hello`.

3. Compile our example. We include :code:`make clean` to remove any leftover
   build files, since they would be inappropriate inside the container.

Once the image is built, we can see the results. (Install the image into
:code:`/var/tmp` as outlined in the tutorial, if you haven’t already.)

::

  $ ch-run /var/tmp/mpihello-openmpi.sqfs -- ls -lh /hello
  total 32K
  -rw-rw---- 1 charlie charlie  908 Oct  4 15:52 Dockerfile
  -rw-rw---- 1 charlie charlie  157 Aug  5 22:37 Makefile
  -rw-rw---- 1 charlie charlie 1.2K Aug  5 22:37 README
  -rwxr-x--- 1 charlie charlie 9.5K Oct  4 15:58 hello
  -rw-rw---- 1 charlie charlie 1.4K Aug  5 22:37 hello.c
  -rwxrwx--- 1 charlie charlie  441 Aug  5 22:37 test.sh

Your software stored on the host
--------------------------------

This method leaves your software on the host but compiles it in the image.
This is recommended when your software is volatile or each image user needs a
different version, for example a simulation code under active development.

The general approach is to bind-mount the appropriate directory and then run
the build inside the container. We can re-use the :code:`mpihello` image to
demonstrate this.

::

  $ cd examples/mpihello
  $ ls -l
  total 20
  -rw-rw---- 1 charlie charlie  908 Oct  4 09:52 Dockerfile
  -rw-rw---- 1 charlie charlie 1431 Aug  5 16:37 hello.c
  -rw-rw---- 1 charlie charlie  157 Aug  5 16:37 Makefile
  -rw-rw---- 1 charlie charlie 1172 Aug  5 16:37 README
  $ ch-run -b .:/mnt/0 --cd /mnt/0 /var/tmp/mpihello.sqfs -- \
    make mpicc -std=gnu11 -Wall hello.c -o hello
  $ ls -l
  total 32
  -rw-rw---- 1 charlie charlie  908 Oct  4 09:52 Dockerfile
  -rwxrwx--- 1 charlie charlie 9632 Oct  4 10:43 hello
  -rw-rw---- 1 charlie charlie 1431 Aug  5 16:37 hello.c
  -rw-rw---- 1 charlie charlie  157 Aug  5 16:37 Makefile
  -rw-rw---- 1 charlie charlie 1172 Aug  5 16:37 README

A common use case is to leave a container shell open in one terminal for
building, and then run using a separate container invoked from a different
terminal.


MPI
===

Problems that best practices help you avoid
-------------------------------------------

These recommendations are derived from our experience in mitigating container
MPI issues. It is important to note that, despite marketing claims, no single
container implementation has “solved” MPI or is free of warts; the issues are
numerous, multifaceted, and dynamic.

Key concepts and related issues include:

  1. **Workload management**. Running applications on HPC clusters requires
     resource management and job scheduling. Put simply, resource management
     is the act of allocating and restricting compute resources, e.g., CPU and
     memory, whereas job scheduling is the act of prioritizing and enforcing
     resource management. *Both require privileged operations.*

     Some privileged container implementations attempt to provide their own
     workload management, often referred to as “container orchestration”.

     Charliecloud is lightweight and completely unprivileged. We rely on
     existing, reputable and well established HPC workload managers such as
     Slurm.

  2. **Job launch**. When a multi-node MPI job is launched, each node must
     launch a number of containerized processes, i.e., *ranks*. Doing this
     unprivileged and at scale requires interaction between the application
     and workload manager. That is, something like Process Management
     Interface (PMI) is needed to facilitate the job launch.

  3. **Shared memory**. Processes in separate sibling containers cannot use
     single-copy *cross-memory attach* (CMA), as opposed to double-copy POSIX
     or SysV shared memory. The solution is to put all ranks in the *same*
     container with :code:`ch-run --join`. (See above for details:
     :ref:`faq_join`.)

  4. **Network fabric.** Performant MPI jobs must recognize and use a system’s
     high-speed interconnect. Common issues that arise are:

       a. Libraries required to use the interconnect are proprietary or
          otherwise unavailable to the container.

       b. The interconnect is not supported by the container MPI.

     In both cases, the containerized MPI application will either fail or run
     significantly slower.

These problems can be avoided, and this section describes our recommendations
to do so.

Recommendations TL;DR
---------------------

Generally, we recommend building a flexible MPI container using:

   a. **libfabric** to flexibly manage process communication over a diverse
      set of network fabrics;

   b. a parallel **process management interface** (PMI), compatible with the
      host workload manager (e.g., PMI2, PMIx, flux-pmi); and

   c. an **MPI** that supports (1) libfabric and (2) the selected PMI.

More experienced MPI and unprivileged container users can find success through
MPI replacement (injection); however, such practices are beyond the scope of
this FAQ.

The remaining sections detail the reasoning behind our approach. We recommend
referencing, or directly using, our examples
:code:`examples/Dockerfile.{libfabric,mpich,openmpi}`.

Use libfabric
-------------

`libfabric <https://ofiwg.github.io/libfabric>`_ (a.k.a. Open Fabrics
Interfaces or OFI) is a low-level communication library that abstracts diverse
networking technologies. It defines *providers* that implement the mapping
between application-facing software (e.g., MPI) and network specific drivers,
protocols, and hardware. These providers have been co-designed with fabric
hardware and application developers with a focus on HPC needs. libfabric lets
us more easily manage MPI communication over diverse network high-speed
interconnects (a.k.a. *fabrics*).

From our libfabric example (:code:`examples/Dockerfile.libfabric`):

.. literalinclude:: ../examples/Dockerfile.libfabric
   :language: docker
   :lines: 116-135

The above compiles libfabric with several “built-in” providers, i.e.
:code:`psm3` (on x86-64), :code:`rxm`, :code:`shm`, :code:`tcp`, and
:code:`verbs`, which enables MPI applications to run efficiently over most
verb devices using TCP, IB, OPA, and RoCE protocols.

Two key advantages of using libfabric are: (1) the container’s libfabric can
make use of “external” i.e. dynamic-shared-object (DSO) providers, and
(2) libfabric replacement is simpler than MPI replacement and preserves the
original container MPI. That is, managing host/container ABI compatibility is
difficult and error-prone, so we instead manage the more forgiving libfabric
ABI compatibility.

A DSO provider can be used by a libfabric that did not originally compile it,
i.e., they can be compiled on a target host and later injected into the
container along with any missing shared library dependencies, and used by the
container's libfabric. To build a libfabric provider as a DSO, add :code:`=dl`
to its :code:`configure` argument, e.g., :code:`--with-cxi=dl`.

A container's libfabric can also be replaced by a host libfabric. This is a
brittle but usually effective way to give containers access to the Cray
libfabric Slingshot provider :code:`cxi`.

In Charliecloud, both of these injection operations are currently done with
:code:`ch-fromhost`, though see `issue #1861
<https://github.com/hpc/charliecloud/issues/1861>`_.

Choose a compatible PMI
-----------------------

Unprivileged processes, including unprivileged containerized processes, are
unable to independently launch containerized processes on different nodes,
aside from using SSH, which isn’t scalable. We must either (1) rely on a host
supported parallel process management interface (PMI), or (2) achieve
host/container MPI ABI compatibility through unsavory practices such as
complete container MPI replacement.

The preferred PMI implementation, e.g., PMI1, PMI2, OpenPMIx, or flux-pmi,
will be that which is best supported by your host workload manager and
container MPI.

In :code:`example/Dockerfile.libfabric`, we selected :code:`OpenPMIx` because
(1) it is supported by SLURM, OpenMPI, and MPICH, (2)~it is required for
exascale, and (3) OpenMPI versions 5 and newer will no longer support PMI2.

Choose an MPI compatible with your libfabric and PMI
----------------------------------------------------

There are various MPI implementations, e.g., OpenMPI, MPICH, MVAPICH2,
Intel-MPI, etc., to consider. We generally recommend OpenMPI; however, your
MPI implementation of choice will ultimately be that which best supports the
libfabric and PMI most compatible with your hardware and workload manager.


..  LocalWords:  userguide Gruening Souppaya Morello Scarfone openmpi nist dl
..  LocalWords:  ident OCFS MAGICK mpich psm rxm shm DSO pmi MVAPICH
