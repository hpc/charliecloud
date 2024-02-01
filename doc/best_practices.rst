Best practices
**************

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

   #. Build and install OpenMPI. Note the :code:`getconf` trick to guess at an
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


..  LocalWords:  userguide Gruening Souppaya Morello Scarfone openmpi nist
..  LocalWords:  ident OCFS MAGICK
