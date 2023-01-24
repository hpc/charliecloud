:code:`ch-fromhost`
+++++++++++++++++++

.. only:: not man

   Inject files from the host into an image directory, with various magic.


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

The purpose of this command is to inject arbitrary host files into a container
necessary to access host specific resources; usually GPU or proprietary
interconnets. **It is not a general copy-to-image tool**; see further discussion
on use cases below.

It should be run after:code:`ch-convert` and before :code:`ch-run`. After
invocation, the image is no longer portable to other hosts.

Injection is not atomic; if an error occurs partway through injection, the
image is left in an undefined state and should be re-unpacked from storage.
Injection is currently implemented using a simple file copy, but that may
change in the future.

Arbitrary file and Libfabric injection are handled differently.

Arbitrary files
---------------

Arbitrary file paths that contain the strings :code:`/bin` or
:code:`/sbin` are assumed to be executables and placed in :code:`/usr/bin`
within the container. Paths that are not loadable libfabric providers and
contain the strings :code:`/lib` or :code:`.so` are assumed to be shared
libraries and are placed in the first-priority directory reported by
:code:`ldconfig` (see :code:`--lib-path` below). Other files are placed in the
directory specified by :code:`--dest`.

If any shared libraries are injected, run :code:`ldconfig` inside the
container (using :code:`ch-run -w`) after injection.

Libfabric
---------

MPI implementations have numerous ways of communicating messages over
interconnects. We use Libfabric (OFI), an OpenFabric framework that
exports fabric communication services to applications, to manage these
communcations with built-in, or loadable, fabric providers.

   - https://ofiwg.github.io/libfabric
   - https://ofiwg.github.io/libfabric/v1.14.0/man/fi_provider.3.html

Using OFI, we can (a) uniformly manage fabric communcation services for both
OpenMPI and MPICH, and (b) use simplified methods of accessing proprietary host
hardware, e.g., Cray's Gemini/Aries and Slingshot (CXI).

OFI providers implement the application facing software interfaces needed to
access network specific protocols, drivers, and hardware. Loadable providers,
i.e., compiled OFI libraries that end in :code:`-fi.so`, for example, Cray's
:code:`libgnix-fi.so`, can be copied into, and used, by an image with a MPI
configured against OFI. Alternatively, the image's :code:`libfabric.so` can
be overwritten with the host's. See details and quirks below.

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

  :code:`--cray-mpi-cxi`
    Inject cray-libfabric for slingshot. This is equivalent to
    :code:`--path $CH_FROMHOST_OFI_CXI`, where :code:`$CH_FROMHOST_OFI_CXI` is
    the path the Cray host libfabric :code:`libfabric.so`.

  :code:`--cray-mpi-gni`
    Inject cray gemini/aries GNI Libfabric provider :code:`libgnix-fi.so`. This
    is equivalent to :code:`--fi-provider $CH_FROMHOST_OFI_GNI`, where
    :code:`CH_FROMHOST_OFI_GNI` is the path to the Cray host ugni provider
    :code:`libgnix-fi.so`.

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

  :code:`--fi-path`
    Print the guest destination path for libfabric providers and replacement.

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
   use :code:`--cmd`, :code:`--file`, :code:`--ofi`, and/or :code:`--path` to
   put together a custom solution. But, please consider filing an issue so we
   can package your functionality with a tidy option like :code:`--nvidia`.


Libfabric usage and quirks
==============================

The implementation of libfabric provider injection and replacement is
experimental and has a couple quirks.

1. Containers must have the following software installed:

   a. Libfabric (https://ofiwg.github.io/libfabric/). See
      :code:`charliecloud/examples/Dockerfile.libfabric`.

   b. Corresponding open source MPI implementation configured and built against
      the container libfabric, e.g.,
      - `MPICH <https://www.mpich.org/>`_, or
      - `OpenMPI <https://www.open-mpi.org/>`_.
      See :code:`charliecloud/examples/Dockerfile.mpich` and
      :code:`charliecloud/examples/Dockerfile.openmpi`.

2. At run time, a Libfabric provider can be specified with the variable
   :code:`FI_PROVIDER`. The path to search for shared providers can be specified
   with :code:`FI_PROVIDER_PATH`. These variables can be inherited from the host
   or explicitly set with the container's environment file
   :code:`/ch/environent` via :code:`--set-env`.

   To avoid issues and reduce complexity, the inferred injection destination
   for libfabric providers and replacement will always at the path in the image
   where :code:`libfabric.so` is found.

3. The Cray GNI loadable provider, :code:`libgnix-fi.so`, will link to
   compiler(s) in the programming environment by default. For example, if it
   is built under the :code:`PrgEnv-intel` programming environment, it will have
   links to files at paths :code:`/opt/gcc` and :code:`/opt/intel` that
   :code:`ch-run` will not bind automatically.

   Managing all possible bind mount paths is untenable. Thus, this experimental
   implementation injects libraries linked to a :code:`libgnix-fi.so` built
   with the minimal modules necessary to compile, i.e.:

   - modules
   - craype-network-aries
   - eproxy
   - slurm
   - cray-mpich
   - craype-haswell
   - craype-hugepages2M

   A Cray GNI provider linked against more complicated PE's will still work,
   assuming 1) the user explicitly bind-mounts missing libraries listed from
   its :code:`ldd` output, and 2) all such libraries do not conflict with
   container functionality, e.g., :code:`glibc.so`, etc.

4. At the time of this writing, a Cray Slingshot optimized provider is not
   available; however, recent Libfabric source acitivity indicates there may be
   at some point, see: https://github.com/ofiwg/libfabric/pull/7839We.

   For now, on Cray systems with Slingshot, CXI, we need overwrite the
   container's :code:`libfabric.so` with the hosts using :code:`--path`. See
   examples for details.

5. Tested only for C programs compiled with GCC, and it probably won't work
   without extensive bind-mounts and kluding. If you'd like to use another
   compiler or programming environment, please get in touch so we can implement
   the necessary support.

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

libfabric
---------

Cray Slingshot CXI injection.

Replace image libabfric, i.e., :code:`libfabric.so`, with Cray host's
libfabric at host path :code:`/opt/cray-libfabric/lib64/libfabric.so`.

::

  $ ch-fromhost -v --path /opt/cray-libfabric/lib64/libfabric.so /tmp/ompi
  [ debug ] queueing files
  [ debug ]    cray libfabric: /opt/cray-libfabric/lib64/libfabric.so
  [ debug ] searching image for inferred libfabric destiation
  [ debug ]    found /tmp/ompi/usr/local/lib/libfabric.so
  [ debug ] adding cray libfabric libraries
  [ debug ]    skipping /lib64/libcom_err.so.2
  [...]
  [ debug ] queueing files
  [ debug ]    shared library: /usr/lib64/libcxi.so.1
  [ debug ] queueing files
  [ debug ]    shared library: /usr/lib64/libcxi.so.1.2.1
  [ debug ] queueing files
  [ debug ]    shared library: /usr/lib64/libjson-c.so.3
  [ debug ] queueing files
  [ debug ]    shared library: /usr/lib64/libjson-c.so.3.0.1
  [...]
  [ debug ] queueing files
  [ debug ]    shared library: /usr/lib64/libssh.so.4
  [ debug ] queueing files
  [ debug ]    shared library: /usr/lib64/libssh.so.4.7.4
  [...]
  [ debug ] inferred shared library destination: /tmp/ompi//usr/local/lib
  [ debug ] injecting into image: /tmp/ompi/
  [ debug ]    mkdir -p /tmp/ompi//var/lib/hugetlbfs
  [ debug ]    mkdir -p /tmp/ompi//var/spool/slurmd
  [ debug ]    echo '/usr/lib64' >> /tmp/ompi//etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    /opt/cray-libfabric/lib64/libfabric.so -> /usr/local/lib (inferred)
  [ debug ]    /usr/lib64/libcxi.so.1 -> /usr/local/lib (inferred)
  [ debug ]    /usr/lib64/libcxi.so.1.2.1 -> /usr/local/lib (inferred)
  [ debug ]    /usr/lib64/libjson-c.so.3 -> /usr/local/lib (inferred)
  [ debug ]    /usr/lib64/libjson-c.so.3.0.1 -> /usr/local/lib (inferred)
  [ debug ]    /usr/lib64/libssh.so.4 -> /usr/local/lib (inferred)
  [ debug ]    /usr/lib64/libssh.so.4.7.4 -> /usr/local/lib (inferred)
  [ debug ] running ldconfig
  [ debug ]    ch-run -w /tmp/ompi/ -- /sbin/ldconfig
  [ debug ] validating ldconfig cache
  done

Same as above, except also inject Cray's :code:`fi_info` to verify Slingshot
provider access.

::

  $ ch-fromhost -v --path /opt/cray/libfabric/1.15.0.0/lib64/libfabric.so \
                -d /usr/local/bin \
                --path /opt/cray/libfabric/1.15.0.0/lib64/libfabric.so \
                /tmp/ompi
  [...]
  $ ch-run /tmp/ompi/ -- fi_info -p cxi
  provider: cxi
    fabric: cxi
    [...]
    type: FI_EP_RDM
    protocol: FI_PROTO_CXI


Cray GNI shared provider injection.

Add Cray host built GNI provider :code:`libgnix-fi.so` to the image and verify
with :code:`fi_info`.

::

  $ ch-fromhost -v --path /home/ofi/libgnix-fi.so /tmp/ompi
  [ debug ] queueing files
  [ debug ]    libfabric shared provider: /home/ofi/libgnix-fi.so
  [ debug ] searching /tmp/ompi for libfabric shared provider destination
  [ debug ]    found: /tmp/ompi/usr/local/lib/libfabric.so
  [ debug ] inferred provider destination: //usr/local/lib/libfabric
  [ debug ] injecting into image: /tmp/ompi
  [ debug ]    mkdir -p /tmp/ompi//usr/local/lib/libfabric
  [ debug ]    mkdir -p /tmp/ompi/var/lib/hugetlbfs
  [ debug ]    mkdir -p /tmp/ompi/var/opt/cray/alps/spool
  [ debug ]    mkdir -p /tmp/ompi/opt/cray/wlm_detect
  [ debug ]    mkdir -p /tmp/ompi/etc/opt/cray/wlm_detect
  [ debug ]    mkdir -p /tmp/ompi/opt/cray/udreg
  [ debug ]    mkdir -p /tmp/ompi/opt/cray/xpmem
  [ debug ]    mkdir -p /tmp/ompi/opt/cray/ugni
  [ debug ]    mkdir -p /tmp/ompi/opt/cray/alps
  [ debug ]    echo '/lib64' >> /tmp/ompi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/alps/lib64' >> /tmp/ompi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/udreg/lib64' >> /tmp/ompi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/ugni/lib64' >> /tmp/ompi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/wlm_detect/lib64' >> /tmp/ompi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/xpmem/lib64' >> /tmp/ompi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/usr/lib64' >> /tmp/ompi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    /home/ofi/libgnix-fi.so -> //usr/local/lib/libfabric (inferred)
  [ debug ] running ldconfig
  [ debug ]    ch-run -w /tmp/ompi -- /sbin/ldconfig
  [ debug ] validating ldconfig cache
  done

  $ ch-run /tmp/ompi -- fi_info -p gni
  provider: gni
    fabric: gni
    [...]
    type: FI_EP_RDM
    protocol: FI_PROTO_GNI

Arbitrary
---------

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

Acknowledgements
================

This command was inspired by the similar `Shifter
<http://www.nersc.gov/research-and-development/user-defined-images/>`_ feature
that allows Shifter containers to use the Cray Aries network. We particularly
appreciate the help provided by Shane Canon and Doug Jacobsen during our
implementation of :code:`--cray-mpi`.

We appreciate the advice of Ryan Olson at nVidia on implementing
:code:`--nvidia`.
