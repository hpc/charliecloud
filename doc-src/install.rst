Installation
************

.. contents::
   :depth: 2
   :local:

.. note::

   These are general installation instructions. If you'd like specific,
   step-by-step directions for CentOS 7, section :doc:`virtualbox` has these
   for a VirtualBox virtual machine.

Prequisites
===========

Charliecloud is a simple system with limited prerequisites. If your system
meets these prerequisites but Charliecloud doesn't work, please report that as
a bug.

Run time
--------

Systems used for running images in the standard unprivileged mode need:

* Recent Linux kernel with :code:`CONFIG_USER_NS=y`. (We've had good luck with
  various distribution upstream versions of 4.4 and higher.)

  * Some distributions (e.g. debian stretch) disable user namespaces
    via the :code:`kernel.unprivileged_userns_clone` sysctl. Set this
    to :code:`1` to enable them.

* C compiler and standard library

* POSIX shell and utilities

Tested and working by us include the Ubuntu and upstream versions of 4.4.

.. note::

   An experimental setuid mode is also provided that does not need user
   namespaces. This should run on most currently supported Linux
   distributions.

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

* Bash 4.1+
* Python 2.6+
* wget

.. With respect to curl vs. wget, both will work fine for our purposes
   (download a URL). According to Debian's popularity contest, 99.88% of
   reporting systems have wget installed, vs. about 44% for curl. On the other
   hand, curl is in the minimal install of CentOS 7 while wget is not. For now
   I just picked wget because I liked it better.


Install Docker (build systems only)
===================================

Tnstalling Docker is beyond the scope of this documentation, but here are a
few tips.

Understand the security implications of Docker
----------------------------------------------

Because Docker (a) makes installing random crap from the internet really easy
and (b) has an "interesting" security culture, you should take care. Some of
the implications are below. This list should not be considered comprehensive
nor a substitute for appropriate expertise; adhere to your moral and
institutional responsibilities.

(All this stuff is a key motivation for Charliecloud.)

:code:`docker` equals root
~~~~~~~~~~~~~~~~~~~~~~~~~~

Anyone who can run the :code:`docker` command or interact with the Docker
daemon can `trivially escalate to root
<http://reventlov.com/advisories/using-the-docker-command-to-root-the-host>`_.
This is considered a feature.

For this reason, don't create the :code:`docker` group, as this will allow
passwordless, unlogged escalation for anyone in the group.

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

Configuring for a proxy
-----------------------

By default, Docker does not work if you have a proxy, and it fails in two
different ways.

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

The second problem is that Docker containers need to know about the proxy as
well. This manifests as images failing to build because they can't download
stuff from the internet.

The fix is to set the proxy variables in your environment, e.g.::

  export HTTP_PROXY=http://proxy.example.com:8088
  export http_proxy=$HTTP_PROXY
  export HTTPS_PROXY=$HTTP_PROXY
  export https_proxy=$HTTP_PROXY
  export ALL_PROXY=$HTTP_PROXY
  export all_proxy=$HTTP_PROXY
  export NO_PROXY='localhost,127.0.0.1,.example.com'
  export no_proxy=$NO_PROXY

You also need to teach :code:`sudo` to retain them. Add the following to
:code:`/etc/sudoers`::

  Defaults env_keep+="HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"

Because different programs use different subsets of these variables, and to
avoid a situation where some things work and others don't, the Charliecloud
test suite (see below) includes a test that fails if some but not all of the
above variables are set.


Install Charliecloud
====================

Download
--------

See our GitHub project: https://github.com/hpc/charliecloud

Download with :code:`git clone --recursive`; the switch gets the submodule
needed for testing as well. Other methods of downloading (e.g. the tarball,
plain :code:`git clone`) are known not to work.

The remaining install steps can be run from the Git working directory or an
unpacked export tarball created with :code:`make export`.

Build
-----

To build in the standard, unprivileged mode (recommended)::

  $ make

To build in setuid mode (for testing if your kernel doesn't support the user
namespace)::

  $ make SETUID=yes

To build the documentation, see :code:`doc-src/README`.

.. warning::

   Do not build as root. This is unsupported and may introduce security
   problems.

Install (optional)
------------------

You can run Charliecloud from the source directory, and it's recommended you
at least run the test suite before installation to establish that your system
will work.

To install (FHS-compliant)::

  $ make install PREFIX=/foo/bar

Note that :code:`PREFIX` is required; it does not default to
:code:`/usr/local` like many packages.

.. _install_test-charliecloud:

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
run phases, and there is an additional phase that runs the examples' test
suites. These phases can be tested independently on different systems.

Testing is coordinated by :code:`make`. The test targets run one or more test
suites. If any test suite has a failure, testing stops with an error message.

The tests need three work directories with several gigabytes of free space, in
order to store image tarballs, unpacked image directories, and permission test
fixtures. These are configured with environment variables::

  $ export CH_TEST_TARDIR=/var/tmp/tarballs
  $ export CH_TEST_IMGDIR=/var/tmp/images
  $ export CH_TEST_PERMDIRS='/var/tmp /tmp'

:code:`CH_TEST_PERMDIRS` can be set to `skip` in order to skip the file
permissions tests.

(Strictly speaking, the build phase needs only the first, and the example test
phase does not need the last one. However, for simplicity, the tests will
demand all three for all phases.)

.. note::

   Bats will wait until all descendant processes finish before exiting, so if
   you get into a failure mode where a test suite doesn't clean up all its
   processes, Bats will hang.

Build
-----

In this phase, image building and associated functionality is tested.

::

  ./bats build.bats build_auto.bats build_post.bats
   ✓ create tarball directory if needed
   ✓ documentations build
   ✓ executables seem sane
  [...]
   ✓ ch-build obspy
   ✓ ch-docker2tar obspy
   ✓ docker pull dockerpull
   ✓ ch-docker2tar dockerpull
   ✓ nothing unexpected in tarball directory

  41 tests, 0 failures

Note that with an empty Docker cache, this test can be quite lengthy, half an
hour or more, because it builds all the examples as well as several basic
Dockerfiles for common Linux distributions and tools (in :code:`test`). With a
full cache, expect more like 1–2 minutes.

.. note::

   The easiest way to update the Docker images used in this test is to simply
   delete all Docker containers and images, and let them be rebuilt::

     $ sudo docker rm $(sudo docker ps -aq)
     $ sudo docker rmi -f $(sudo docker images -q)

Run
---

The run tests require the contents of :code:`$CH_TEST_TARDIR` produced by a
successful, complete build test. Copy this directory to the run system.

File permission enforcement is tested against specially constructed fixture
directories. These should include every meaningful mounted filesystem, and
they cannot be shared between different users. To create them::

  $ for d in $CH_TEST_PERMDIRS; do sudo ./make-perms-test $d $USER nobody; done

To skip this test (e.g., if you don't have root), set
:code:`$CH_TEST_PERMDIRS` to :code:`skip`.

To run the tests::

  $ make test-run

Examples
--------

Some of the examples include test suites of their own. This Charliecloud runs
those test suites, using a Slurm allocation if one is available or a single
node (localhost) if not.

These require that the run tests have been completed successfully.

Note that this test can take quite a while, and that single tests from
the Charliecloud perspective include entire test suites from the example's
perspective, so be patient.

To run the tests::

  $ make test-test

Quick and multiple-phase tests
------------------------------

We also provide the following additional test targets:

 * :code:`test-quick`: key subset of build and run phases (nice for development)
 * :code:`test`: build and run phases
 * :code:`test-all`: all three phases

We recommend that a build box pass all phases so it can be used to run
containers for testing and development.
