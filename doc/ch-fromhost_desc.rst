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

The purpose of this command is to inject arbitrary files and loadable Libfabric
shared object providers into a container that are necessary to access host
specific resources; usually GPU or proprietary interconnets. **It is not a
general copy-to-image tool**; see further discussion on use cases below.

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

Loadable Libfabric providers
----------------------------

MPI implementations have numerous ways of communicating messages over
interconnects. We use Libfabric (OFI), an OpenFabric framework that
exports fabric communication services to applications, to manage these
communcations with built-in, or loadable, fabric providers.

   - https://ofiwg.github.io/libfabric
   - https://ofiwg.github.io/libfabric/v1.14.0/man/fi_provider.3.html

Using OFI, we can: 1) uniformly manage fabric communcations services for both
OpenMPI and MPICH; and 2) leverage host-built loadable dynamic shared object
(dso) providers to give our container examples access to proprietary host
hardware, e.g., Cray Gemini/Aries.

OFI providers implement the application facing software interfaces needed to
access network specific protocols, drivers, and hardware. Loadable providers,
e.g., files that end in :code:`-fi.so`, can be copied into, and used, by an
image with a MPI configured with Libfabric. See details below.


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

  :code:`-o`. :code:`--ofi PATH`
    Inject the loadable Libfabric provider(s) at :code:`PATH`.

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

  :code:`--cray-ugni`
    Inject cray gemini/aries GNI provider :code:`libgnix-fi.so`; this is
    equivalent to :code:`--ofi $CH_FROMHOST_OFI_UGNI`.

  :code:`--lib-path`
    Print the guest destination path for shared libraries inferred as
    described above.

  :code:`--ofi-path`
    Print the guest destination path for loadable libfabric providers as
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


:code:`--ofi` usage and quirks
==============================

The implementation of :code:`--ofi` is experimental and has a couple quirks.

1. Containers must have the following software installed:

   a. Libfabric (https://ofiwg.github.io/libfabric/). See
      :code:`charliecloud/examples/Dockerfile.libfabric`.

   b. Corresponding open source MPI implementation configured and built against
      the container libfabric, e.g.,
      - `MPICH <https://www.mpich.org/>`_, or
      - `OpenMPI <https://www.open-mpi.org/>`_.
      See :code:`charliecloud/examples/Dockerfile.mpich` and
      :code:`charliecloud/examples/Dockerfile.openmpi`.

2. Libfabric will create and use loadable providers in the
   :code:`PREFIX/lib/libfabric` directory, where :code:`PREFIX` is the
   :code:`--prefix` argument (path) specified at libfabric configure time.

   The specific provider to use, and the path to search for providers, can
   be specified with the :code:`FI_PROVIDER` and :code:`FI_PROVIDER_PATH`
   variables respectively. These variables complicate injection because they can
   be inherited from the host at run time or explicitly set in the container's
   environment via the file :code:`/ch/environent` in conjunction with
   :code:`--set-env`.

   The injection destination is then determined with the following precedence.

   a. use path specified by :code:`--dest DST`; if host :code:`FI_PROVIDER_PATH`
      is set, require :code:`--dest`

   b. use :code:`FI_PROVIDER_PATH` from the image's :code:`/ch/environment`
      file; warn about `--set-env` requirement

   c. the :code:`/libfabric` directory in image where :code:`libfabric.so` is
      found; if the directory doesn't exist, create it.

3. The Cray UGNI loadable provider, :code:`libgnix-fi.so`, will link to
   compiler(s) in the programming environment by default. For example, if it
   is built under the :code:`PrgEnv-intel` PE, the provider will have links to
   files at paths :code:`/opt/gcc` and :code:`/opt/intel` that :code:`ch-run`
   will not bind automatically.

   Managing all possible bind mount paths is untenable. Thus, this experimental
   implementation works only with Cray UGNI provider(s) built on XC series
   systems with the minimal modules necessary to compile provider and
   leverage the Aries interconnect at run-time, i.e.,:

   - modules
   - craype-network-aries
   - eproxy
   - slurm
   - cray-mpich
   - craype-haswell
   - craype-hugepages2M

   Cray UGNI providers linked against more complicated PE's will work assuming
   1) the user explicitly bind-mounts any and all missing paths from the
   provider's :code:`ldd` output, and 2) all such paths do not conflict with
   container functionality, e.g., :code:`/usr/bin/`, etc.

4. At the time of this writing, a Cray Slingshot optimized provider is not
   available. We are working with HPE to get this feature added sooner, rather
   than later; however, we may need to implement more complicated injection
   techniques, e.g., complete replacement of the container's libfabric with
   hosts, for future Cray systems with Slingshot.

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

Inject the Cray-ugni loadable provider into the image, and then run
:code:`ldconfig`::

  $ ch-fromhost --ofi $HOME/scratch/opt/lib/libfabric/libginx-fi.so /var/tmp/openmpi
  [ debug ]   found /home/cholo/scratch/opt/lib/libfabric/libgnix-fi.so
  [ debug ] searching /var/tmp/openmpi for libfabric dso provider destination...
  [ debug ]   found: /var/tmp/openmpi//usr/local/lib/libfabric.so
  [ debug ] using libfabric dso provider destination: /usr/local/lib/libfabric
  [ debug ] injecting into image: /var/tmp/openmpi
  [ debug ]   mkdir -p /var/tmp/openmpi/usr/local/lib/libfabric
  [ debug ]   mkdir -p /var/tmp/openmpi/var/opt/cray/alps/spool
  [ debug ]   mkdir -p /var/tmp/openmpi/etc/opt/cray/wlm_detect
  [ debug ]   mkdir -p /var/tmp/openmpi/var/opt/cray/hugetlbfs
  [ debug ]   mkdir -p /var/tmp/openmpi/opt/cray/udreg
  [ debug ]   mkdir -p /var/tmp/openmpi/opt/cray/xpmem
  [ debug ]   mkdir -p /var/tmp/openmpi/opt/cray/ugni
  [ debug ]   mkdir -p /var/tmp/openmpi/opt/cray/alps
  [ debug ]    echo '/lib64' >> /var/tmp/openmpi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/[...]' >> /var/tmp/openmpi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/udreg/[...]' >> /var/tmp/openmpi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/ugni/[...]' >> /var/tmp/openmpi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/wlm_detect/[...]' >> /var/tmp/openmpi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/opt/cray/xpmem/[...]' >> /var/tmp/openmpi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/users/cholo/scratch/opt/lib' >> /var/tmp/openmpi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]    echo '/usr/lib64' >> /var/tmp/openmpi/etc/ld.so.conf.d/ch-ofi.conf
  [ debug ]   /etc/opt/cray/wlm_detect/[...] -> /etc/opt/cray/wlm_detect
  [ debug ]   /home/cholo/scratch/opt/lib/libfabric/libgnix-fi.so -> /usr/local/lib/libfabric (inferred)
  [ debug ] running ldconfig
  done

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
