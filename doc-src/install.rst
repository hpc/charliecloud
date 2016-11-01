Installation
************

.. contents::
   :depth: 2
   :local:

Prequisites
===========

Charliecloud is a simple system with limited prerequisites. If your system
meets these prerequisites but Charliecloud doesn't work, please report that as
a bug.

Run time
--------

Systems used for running images need:

* Recent Linux kernel with :code:`CONFIG_USER_NS=y` and
  :code:`CONFIG_OVERLAY_FS=y`
* C compiler and standard library
* POSIX shell and utilities

If you are using the upstream kernel, you will need 3.18+.

Distribution kernels vary. For example, RHEL7 and derivatives have a patch to
disable user namespaces in concert with mount namespaces, and overlayfs is
available as a "technology preview".

Tested and working by us include the Ubuntu and upstream versions of 4.4.

.. note::

   We are open to patches to make Charliecloud available on older kernels. The
   key parts are likely a setuid binary to avoid the user namespace and some
   workaround for missing overlayfs. Please contact us if you are interested.

Build time
----------

Systems used for building images need the run-time prerequisites, plus:

* `Docker <https://www.docker.com/>`_, recent version. We do not make compatibility guarantees with any specific version, but let us know if you run into issues.
* Bash
* root access using :code:`sudo`
* Internet access or a Docker configured for a local Docker hub

Test suite
----------

In order to run the test suite on a run or build system (you can test each
mode independently), you also need:

* Bash
* Python 2.6+


Download Charliecloud
=====================

See our GitHub project: https://github.com/hpc/charliecloud

The recommended way to download is with :code:`git clone --recursive`; the
switch gets the submodule needed for testing as well.


Make sure you have the required kernel features
===============================================

The :code:`examples` directory includes a C program that exercises the key
system calls Charliecloud depends on. If this works, then Charliecloud
probably will too. If it doesn't, you'll want to understand why before
bothering with the remaining install steps.

::

  $ cd examples/syscalls
  $ make && ./pivot_root
  ok

If :code:`pivot_root` instead reports an error, check the reported line number
in :code:`pivot_root.c` to see what failed.


Install Docker
==============

While installing Docker is beyond the scope of this documentation, here are a
few tips.

.. note::

   Docker need be installed only on build systems. It is not needed at
   runtime.

Understand the security implications of Docker
----------------------------------------------

Because Docker (a) makes installing random crap from the internet really easy
and (b) has an "interesting" security culture, you should take care. Some of
the implications are below. This list should not be considered comprehensive
nor a substitute for appropriate expertise; adhere to your moral and
institutional responsibilities.

(All this stuff is a key motivation for Charliecloud.)

Don't pipe web pages to your shell
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This is how Docker recommends you install the software. Don't do this::

  $ curl -fsSL https://get.docker.com/ | sh

This approach --- piping a web page directly into a shell --- is easy and
fashionable but stupid.

The problem is that you've invited the web page to execute arbitrary code as
you (or worse, root). Auditing the page in a browser only helps somewhat, as
the server could use your :code:`User-Agent` header to decide whether to show
you safe or malicious code.

Download the script to a file and audit it carefully before running.

:code:`docker` equals root
~~~~~~~~~~~~~~~~~~~~~~~~~~

Anyone who can run the :code:`docker` command or interact with the Docker
daemon can `trivially escalate to root
<http://reventlov.com/advisories/using-the-docker-command-to-root-the-host>`_.
This is considered a feature.

For this reason, don't create the :code:`docker` group when the installer
offers it, as this will allow passwordless, unlogged escalation for anyone in
the group.

Images can contain bad stuff
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Standard hygiene for "installing stuff from the internet" applies. Only work
with images you trust. The official DockerHub repositories can help.

Containers run as root
~~~~~~~~~~~~~~~~~~~~~~

By default, Docker runs container processes as root. In addition to being poor
hygiene, this can be an escalation path, e.g. if you bind-mount host
directories.

Docker alters your network configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To see what it did::

  $ ifconfig    # note docker0 interface
  $ brctl show  # note docker0 bridge
  $ route -n

Docker installs services
~~~~~~~~~~~~~~~~~~~~~~~~

If you don't want the service starting automatically at boot, e.g.::

  $ systemctl is-enabled docker
  enabled
  $ systemctl disable docker
  $ systemctl is-enabled docker
  disabled

Configuring Docker for a proxy
------------------------------

By default, Docker does not work if you have a proxy. The symptom is this::

  $ sudo docker run hello-world
  Unable to find image 'hello-world:latest' locally
  Pulling repository hello-world
  Get https://index.docker.io/v1/repositories/library/hello-world/images: dial tcp 54.152.161.54:443: connection refused

The solution is to configure an override file :code:`http-proxy.conf` as
`documented <https://docs.docker.com/articles/systemd/>`_. If you don't have a
systemd system, then :code:`/etc/default/docker` might be the place to go.


Install Charliecloud
====================

All you need in order to use Charliecloud is the executables and :code:`.sh`
files in :code:`bin`::

  $ cd bin
  $ make

You could put this directory in your :code:`$PATH` or link/copy the contents
to somewhere else.

That said, in order to understand Charliecloud, including completing the
tutorial in the next section, you will want access to the rest of the source
code as well.

If you wish to build the documentation, see :code:`doc-src/README`.


Test Charliecloud
=================

Charliecloud comes with a fairly comprehensive `Bats
<https://github.com/sstephenson/bats>`_ test suite, in :code:`test`. Go there::

  $ cd test

Bats must be installed in the :code:`test/bats.src`. In the Git repository,
this is arranged with a Git submodule, so if you downloaded Charliecloud with
Git command above, it should already be there. Otherwise, you must download
and unpack Bats manually.

:code:`test/bats` is a symlink to the main Bats script, for convenience.

Verify the Bats install with::

  $ ./bats --version
  Bats 0.4.0

Just like for normal use, the Charliecloud test suite is split into build and
run phases. These can be tested independently on different systems.

Testing is coordinated by :code:`make`. The test targets run one or more test
suites. If any test suite has a failure, testing stops with an error message.

Both the build and run phases require a work directory with several gigabytes
of free space. This is configured with an environment variable::

  $ export CH_TEST_WORKDIR=/data

Build time
----------

In this phase, image building and associated functionality is tested::

  $ make test-build
  ./bats build.bats
   ✓ executables --help
   ✓ docker-build
   ✓ docker-build --pull
   ✓ ch-dockerfile2dir

  4 tests, 0 failures
  ./bats build_auto.bats
   ✓ docker-build debian8
   ✓ ch-docker2tar debian8
   ✓ docker-build python3
   ✓ ch-docker2tar python3
  [...]
   ✓ docker-build mpibench
   ✓ ch-docker2tar mpibench

  22 tests, 0 failures

Note that with an empty Docker cache, this test can be quite lengthy, on the
order of 20--30 minutes for me, because it builds all the examples as well as
several basic Dockerfiles for common Linux distributions and tools (in
:code:`test`). With a full cache, it takes about 1 minute for me.

A faster test that does not include these is available as well::

  $ make test-build-quick

The easiest way to update the base Docker images used in this test is to simply
delete all Docker images and let them be rebuilt on the next test.

::

  $ sudo docker rm $(sudo docker ps -aq)
  $ sudo docker rmi -f $(sudo docker images -q)

Run time
--------

The run tests require the contents of :code:`$CH_TEST_WORKDIR/tarballs`
produced by a successful build test. Copy this directory to the run system.

Run-time testing requires an additional environment variable specifing the
location(s) of specially constructed filesystem permissions test directories.
These should include every meaningful mounted filesystem, and they cannot be
shared between different users. For example::

  $ export CH_TEST_PERMDIRS='/data /tmp /var/tmp'

These directories must be created as root. For example::

  $ for d in $CH_TEST_PERMDIRS; do sudo ./make-perms-test $d $USER nobody; done

These tests also have full and quick variants::

  $ make test-run
  $ make test-run-quick

Both
----

Charliecloud also provides :code:`test-all` and :code:`test-all-quick` targets
that combine both phases. We recommend that a build box pass these tests as
well so that it can be used to run containers for testing and development.

::

   $ make test-all
   $ make test-all-quick
