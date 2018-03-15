Installation
************

This section describes how to build and install Charliecloud. For some
distributions, this can be done using your package manager; otherwise, both
normal users and admins can build and install it manually.

.. warning::

   **If you are installing on a Cray** and have not applied the patch for Cray
   case #188073, you must use the `cray branch
   <https://github.com/hpc/charliecloud/compare/cray>`_ to avoid crashing
   nodes during job completion. This is a Cray bug that Charliecloud happens
   to tickle. Non-Cray build boxes and others at the same site can still use
   the master branch.

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

* Recent Linux kernel with :code:`CONFIG_USER_NS=y`. We recommend version 4.4
  or higher.

* C compiler and standard library

* POSIX shell and utilities

Some distributions need configuration changes to enable user namespaces. For
example, Debian Stretch needs sysctl
:code:`kernel.unprivileged_userns_clone=1`, and RHEL and CentOS 7.4 need both
a `kernel command line option and a sysctl
<https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_atomic_host/7/html-single/getting_started_with_containers/#user_namespaces_options>`_
(that put you into "technology preview").

.. note::

   An experimental setuid mode is also provided that does not need user
   namespaces. This should run on most currently supported Linux
   distributions.

Build time
----------

Systems used for building images need the run-time prerequisites, plus:

* Bash 4.1+

and optionally:

* `Docker <https://www.docker.com/>`_ 17.03+
* internet access or Docker configured for a local Docker hub
* root access using :code:`sudo`

Older versions of Docker may work but are untested. We know that 1.7.1 does
not work.

Test suite
----------

In order to run the test suite on a run or build system (you can test each
mode independently), you also need:

* Bash 4.1+
* Python 3.4+
* `Bats <https://github.com/sstephenson/bats>`_ 0.4.0
* wget

.. With respect to curl vs. wget, both will work fine for our purposes
   (download a URL). According to Debian's popularity contest, 99.88% of
   reporting systems have wget installed, vs. about 44% for curl. On the other
   hand, curl is in the minimal install of CentOS 7 while wget is not. For now
   I just picked wget because I liked it better.

Note that without Docker on the build system, some of the test suite will be
skipped.

Bats can be installed at the system level or embedded in the Charliecloud
source code. If it's in both places, the latter is used.

To embed Bats, either:

* Download Charliecloud using :code:`git clone --recursive`, which will check
  out Bats as a submodule in :code:`test/bats`.

* Unpack the Bats zip file or tarball in :code:`test/bats`.

To check an embedded Bats::

  $ test/bats/bin/bats --version
  Bats 0.4.0


Package manager install
=======================

Charliecloud is available in some distribution package repositories, and
packages can be built for additional distributions. (Note, however, that
system-wide installation is not required — Charliecloud works fine when built
by any user and run from one's home directory or similar.)

This section describes how to obtain packages for the distributions we know
about, and where to go for support on them.

If you'd like to build one of the packages, or if you're a package maintainer,
see :code:`packaging/README` and :code:`packaging/*/README` for additional
documentation.

Pull requests and other collaboration to improve the packaging situation are
particularly welcome!

Debian
------

Charliecloud has been proposed for inclusion in Debian; see `issue 95
<https://github.com/hpc/charliecloud/issues/95>`_.

.. list-table::
   :widths: auto

   * - Distribution versions
     - proposed for *Buster* and *Stretch backports*
   * - Maintainers
     - Lucas Nussbaum (:code:`lucas@debian.org`)
       and Peter Wienemann (:code:`wienemann@physik.uni-bonn.de`)
   * - Bug reports to
     - Charliecloud's GitHub issue tracker
   * - Packaging source code
     - in Charliecloud: :code:`packaging/debian`

Gentoo
------

A native package for Gentoo is available.

.. list-table::
   :widths: auto

   * - Package name
     - `sys-cluster/charliecloud <https://packages.gentoo.org/packages/sys-cluster/charliecloud>`_
   * - Maintainer
     - Oliver Freyermuth (:code:`o.freyermuth@googlemail.com`)
   * - Bug reports to
     - `Gentoo Bugzilla <https://bugs.gentoo.org/buglist.cgi?quicksearch=sys-cluster%2Fcharliecloud>`_
   * - Packaging source code
     - `Gentoo ebuild repository <https://gitweb.gentoo.org/repo/gentoo.git/tree/sys-cluster/charliecloud>`_

To install::

  $ emerge sys-cluster/charliecloud

If may necessary to accept keywords first, e.g.::

  $ echo "=sys-cluster/charliecloud-0.2.3_pre20171121 ~amd64" >> /etc/portage/package.accept_keywords

A live ebuild is also available and can be keyworded via::

  $ echo "~sys-cluster/charliecloud-9999 \*\*" >> /etc/portage/package.accept_keywords

RPM-based distributions
-----------------------

An RPM :code:`.spec` file is provided in the Charliecloud source code. We are
actively seeking distribution packagers to adapt this into official packages!

.. list-table::
   :widths: auto

   * - Repositories
     - none yet
   * - Maintainer
     - Oliver Freyermuth (:code:`o.freyermuth@googlemail.com`)
   * - Bug reports to
     - Charliecloud's GitHub issue tracker
   * - Packaging source code
     - in Charliecloud: :code:`packaging/redhat`


Manual build and install
========================

Download
--------

See our GitHub project: https://github.com/hpc/charliecloud

The recommended download method is :code:`git clone --recursive`.

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

Note that :code:`PREFIX` is required. It does not default to
:code:`/usr/local` like many packages.

.. include:: ./docker_tips.rst

.. _install_test-charliecloud:

Running the tests
=================

Charliecloud comes with a fairly comprehensive Bats test suite, in
:code:`test`. Go there::

  $ cd test

To check location and version of Bats used by the tests::

  $ make where-bats
  which bats
  /usr/bin/bats
  bats --version
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

:code:`CH_TEST_PERMDIRS` can be set to :code:`skip` in order to skip the file
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

  $ make test-build
  bats build.bats build_auto.bats build_post.bats
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
successful, complete build test. Copy this directory to the run
system.

Additionally, the user running the tests needs to be a member of at least 2
groups.

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
