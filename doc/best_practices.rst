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
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Under this method, one uses :code:`RUN` commands to fetch the desired software
using :code:`curl` or :code:`wget`, compile it, and install. Our example does
this with two chained Dockerfiles. First, we build a basic AlmaLinux image
(:code:`examples/Dockerfile.almalinux_8ch`):

 .. literalinclude:: ../examples/Dockerfile.almalinux_8ch
    :language: docker
    :lines: 2-

Then, in a second image (:code:`examples/Dockerfile.openmpi`), we add OpenMPI.
This is a complex Dockerfile that compiles several dependencies in addition to
OpenMPI. For the purposes of this documentation, you can skip most of it, but
we felt it would be useful to show a real example.

.. literalinclude:: ../examples/Dockerfile.openmpi
   :language: docker
   :lines: 2-

So what is going on here?

1. Use the latest AlmaLinux 8 as the base image.

2. Install a basic build system using the OS package manager.

3. For a few dependencies and then OpenMPI itself:

   1. Download and untar. Note the use of variables to make adjusting the URL
      and versions easier, as well as the explanation of why we’re not using
      :code:`dnf`, given that several of these packages are included in
      CentOS.

   2. Build and install OpenMPI. Note the :code:`getconf` trick to guess at an
      appropriate parallel build.

4. Clean up, in order to reduce the size of the build cache as well as the
   resulting Charliecloud image (:code:`rm -Rf`).

.. Finally, because it’s a container image, you can be less tidy than you
   might be on a normal system. For example, the above downloads and builds in
   :code:`/` rather than :code:`/usr/local/src`, and it installs MPI into
   :code:`/usr` rather than :code:`/usr/local`.

Your software stored in the image
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

..  LocalWords:  userguide Gruening Souppaya Morello Scarfone openmpi
