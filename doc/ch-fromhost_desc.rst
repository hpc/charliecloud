Synopsis
========

::

  $ ch-fromhost [OPTION ...] [FILE_OPTION ...] IMGDIR


Description
===========

.. note::

   This command is experimental. Features may be incomplete and/or buggy.
   Please report any issues you find, so we can fix them!

Inject files from the host into the Charliecloud image directory
:code:`IMGDIR`.

The purpose of this command is to inject files into a container image that are
necessary to run the container on a specific host; e.g., GPU libraries that
are tied to a specific kernel version. **It is not a general copy-to-image
tool**; see further discussion on use cases below. It should be run after
:code:`ch-convert` and before :code:`ch-run`. After invocation, the image is
no longer portable to other hosts.

Injection is not atomic; if an error occurs partway through injection, the
image is left in an undefined state. Injection is currently implemented using
a simple file copy, but that may change in the future.

By default, file paths that contain the strings :code:`/bin` or :code:`/sbin`
are assumed to be executables and placed in :code:`/usr/bin` within the
container. File paths that contain the strings :code:`/lib` or :code:`.so` are
assumed to be shared libraries and are placed in the first-priority directory
reported by :code:`ldconfig` (see :code:`--lib-path` below). Other files are
placed in the directory specified by :code:`--dest`.

If any shared libraries are injected, run :code:`ldconfig` inside the
container (using :code:`ch-run -w`) after injection.


Options
=======

To specify which files to inject
--------------------------------

  :code:`-c`, :code:`--cmd CMD`
    Inject files listed in the standard output of command :code:`CMD`.

  :code:`-f`, :code:`--file FILE`
    Inject files listed in the file :code:`FILE`.

  :code:`-p`, :code:`--path PATH`
    Inject the file at :code:`PATH`.

  :code:`--cray-mpi`
    Cray-enable MPICH/OpenMPI installed inside the image. See important details
    below.

  :code:`--nvidia`
    Use :code:`nvidia-container-cli list` (from :code:`libnvidia-container`)
    to find executables and libraries to inject.

These can be repeated, and at least one must be specified.

To specify the destination within the image
-------------------------------------------

  :code:`-d`, :code:`--dest DST`
    Place files specified later in directory :code:`IMGDIR/DST`, overriding the
    inferred destination, if any. If a file's destination cannot be inferred
    and :code:`--dest` has not been specified, exit with an error. This can be
    repeated to place files in varying destinations.

Additional arguments
--------------------

  :code:`--lib-path`
    Print the guest destination path for shared libraries inferred as
    described above.

  :code:`--no-ldconfig`
    Don't run :code:`ldconfig` even if we appear to have injected shared
    libraries.

  :code:`-h`, :code:`--help`
    Print help and exit.

  :code:`-v`, :code:`--verbose`
    List the injected files.

  :code:`--version`
    Print version and exit.


When to use :code:`ch-fromhost`
===============================

This command does a lot of heuristic magic; while it *can* copy arbitrary
files into an image, this usage is discouraged and prone to error. Here are
some use cases and the recommended approach:

1. *I have some files on my build host that I want to include in the image.*
   Use the :code:`COPY` instruction within your Dockerfile. Note that it's OK
   to build an image that meets your specific needs but isn't generally
   portable, e.g., only runs on specific micro-architectures you're using.

2. *I have an already built image and want to install a program I compiled
   separately into the image.* Consider whether a building a new derived image
   with a Dockerfile is appropriate. Another good option is to bind-mount the
   directory containing your program at run time. A less good option is to
   :code:`cp(1)` the program into your image, because this permanently alters
   the image in a non-reproducible way.

3. *I have some shared libraries that I need in the image for functionality or
   performance, and they aren't available in a place where I can use*
   :code:`COPY`. This is the intended use case of :code:`ch-fromhost`. You can
   use :code:`--cmd`, :code:`--file`, and/or :code:`--path` to put together a
   custom solution. But, please consider filing an issue so we can package
   your functionality with a tidy option like :code:`--cray-mpi` or
   :code:`--nvidia`.


:code:`--cray-mpi` dependencies and quirks
==========================================

The implementation of :code:`--cray-mpi` is messy, foul smelling, and brittle.
It replaces or overrides the MPICH or OpenMPI libraries installed in the
container. Users should be aware of the following.


1. Containers must have the following software installed:

   a. Corresponding open source MPI implementation. (`MPICH
      <https://www.mpich.org/>`_ and `OpenMPI <https://www.open-mpi.org/>`_.)

   b. `PatchELF with our patches <https://github.com/hpc/patchelf>`_.
      Use the :code:`shrink-soname` branch. (MPICH only.)

   c. :code:`libgfortran.so.3`, because Cray's :code:`libmpi.so.12`
      links to it. (MPICH only.)

2. Applications must be dynamically linked to :code:`libmpi.so.12` (not e.g.
   :code:`libmpich.so.12`).

   a. How to configure MPICH to accomplish this is not yet clear to us;
      :code:`test/Dockerfile.mpich` does it, while the Debian packages do not.
      (MPICH only.)

3. An ABI compatible module for the given MPI implementation must be loaded
   when :code:`ch-fromhost` is invoked.

   a. Load the :code:`cray-mpich-abi` module. (MPICH only.)

   b. We recommend loading the module of a version as close to what
      is installed in the image as possible. This OpenMPI install needs to be
      built such that libmpi contains all needed plugins (as opposed to them
      being standalone shared libraries). See `OpenMPI's documentation
      <https://www.open-mpi.org/faq/?category=building>`_ for how to do this.
      (OpenMPI only.)

4. Tested only for C programs compiled with GCC, and it probably won't work
   otherwise. If you'd like to use another compiler or another programming
   language, please get in touch so we can implement the necessary support.

Please file a bug if we missed anything above or if you know how to make the
code better.


Notes
=====

Symbolic links are dereferenced, i.e., the files pointed to are injected, not
the links themselves.

As a corollary, do not include symlinks to shared libraries. These will be
re-created by :code:`ldconfig`.

There are two alternate approaches for nVidia GPU libraries:

  1. Link :code:`libnvidia-containers` into :code:`ch-run` and call the
     library functions directly. However, this would mean that Charliecloud
     would either (a) need to be compiled differently on machines with and
     without nVidia GPUs or (b) have :code:`libnvidia-containers` available
     even on machines without nVidia GPUs. Neither of these is consistent with
     Charliecloud's philosophies of simplicity and minimal dependencies.

  2. Use :code:`nvidia-container-cli configure` to do the injecting. This
     would require that containers have a half-started state, where the
     namespaces are active and everything is mounted but :code:`pivot_root(2)`
     has not been performed. This is not feasible because Charliecloud has no
     notion of a half-started container.

Further, while these alternate approaches would simplify or eliminate this
script for nVidia GPUs, they would not solve the problem for other situations.


Bugs
====

File paths may not contain colons or newlines.

:code:`ldconfig` tends to print :code:`stat` errors; these are typically
non-fatal and occur when trying to probe common library paths. See `issue #732
<https://github.com/hpc/charliecloud/issues/732>`_.


Examples
========

Place shared library :code:`/usr/lib64/libfoo.so` at path
:code:`/usr/lib/libfoo.so` (assuming :code:`/usr/lib` is the first directory
searched by the dynamic loader in the image), within the image
:code:`/var/tmp/baz` and executable :code:`/bin/bar` at path
:code:`/usr/bin/bar`. Then, create appropriate symlinks to :code:`libfoo` and
update the :code:`ld.so` cache.

::

  $ cat qux.txt
  /bin/bar
  /usr/lib64/libfoo.so
  $ ch-fromhost --file qux.txt /var/tmp/baz

Same as above::

  $ ch-fromhost --cmd 'cat qux.txt' /var/tmp/baz

Same as above::

  $ ch-fromhost --path /bin/bar --path /usr/lib64/libfoo.so /var/tmp/baz

Same as above, but place the files into :code:`/corge` instead (and the shared
library will not be found by :code:`ldconfig`)::

  $ ch-fromhost --dest /corge --file qux.txt /var/tmp/baz

Same as above, and also place file :code:`/etc/quux` at :code:`/etc/quux`
within the container::

  $ ch-fromhost --file qux.txt --dest /etc --path /etc/quux /var/tmp/baz

Inject the executables and libraries recommended by nVidia into the image, and
then run :code:`ldconfig`::

  $ ch-fromhost --nvidia /var/tmp/baz
  asking ldconfig for shared library destination
  /sbin/ldconfig: Can't stat /libx32: No such file or directory
  /sbin/ldconfig: Can't stat /usr/libx32: No such file or directory
  shared library destination: /usr/lib64//bind9-export
  injecting into image: /var/tmp/baz
    /usr/bin/nvidia-smi -> /usr/bin (inferred)
    /usr/bin/nvidia-debugdump -> /usr/bin (inferred)
    /usr/bin/nvidia-persistenced -> /usr/bin (inferred)
    /usr/bin/nvidia-cuda-mps-control -> /usr/bin (inferred)
    /usr/bin/nvidia-cuda-mps-server -> /usr/bin (inferred)
    /usr/lib64/libnvidia-ml.so.460.32.03 -> /usr/lib64//bind9-export (inferred)
    /usr/lib64/libnvidia-cfg.so.460.32.03 -> /usr/lib64//bind9-export (inferred)
  [...]
    /usr/lib64/libGLESv2_nvidia.so.460.32.03 -> /usr/lib64//bind9-export (inferred)
    /usr/lib64/libGLESv1_CM_nvidia.so.460.32.03 -> /usr/lib64//bind9-export (inferred)
  running ldconfig

Inject the Cray-enabled MPI libraries into the image, and then run
:code:`ldconfig`::

  $ ch-fromhost --cray-mpi /var/tmp/baz
  asking ldconfig for shared library destination
  /sbin/ldconfig: Can't stat /libx32: No such file or directory
  /sbin/ldconfig: Can't stat /usr/libx32: No such file or directory
  shared library destination: /usr/lib64//bind9-export
  found shared library: /usr/lib64/liblustreapi.so.1
  found shared library: /opt/cray/xpmem/default/lib64/libxpmem.so.0
  [...]
  injecting into image: /var/tmp/baz
    rm -f /var/tmp/openmpi/usr/lib64//bind9-export/libopen-rte.so.40
    rm -f /var/tmp/openmpi/usr/lib64/bind9-export/libopen-rte.so.40
  [...]
    mkdir -p /var/tmp/openmpi/var/opt/cray/alps/spool
    mkdir -p /var/tmp/openmpi/etc/opt/cray/wlm_detect
  [...]
    /usr/lib64/liblustreapi.so.1 -> /usr/lib64//bind9-export (inferred)
    /opt/cray/xpmem/default/lib64/libxpmem.so.0 -> /usr/lib64//bind9-export (inferred)
  [...]
    /etc/opt/cray/wlm_detect/active_wlm -> /etc/opt/cray/wlm_detect
  running ldconfig


Acknowledgements
================

This command was inspired by the similar `Shifter
<http://www.nersc.gov/research-and-development/user-defined-images/>`_ feature
that allows Shifter containers to use the Cray Aries network. We particularly
appreciate the help provided by Shane Canon and Doug Jacobsen during our
implementation of :code:`--cray-mpi`.

We appreciate the advice of Ryan Olson at nVidia on implementing
:code:`--nvidia`.


..  LocalWords:  libmpi libmpich nvidia
