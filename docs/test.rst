.. _install_test-charliecloud:

Testing
*******

Charliecloud comes with a fairly comprehensive Bats test suite. This section
explains how the tests work and how to run them.

.. contents::
   :depth: 2
   :local:


Getting started
===============

Charliecloud's tests are based in the directory :code:`test`, which is either
at the top level of the source code or installed at
:code:`$PREFIX/libexec/charliecloud`. To run them, go there::

  $ cd test

If you have :code:`sudo`, the tests will make use of it by default. To skip
the tests that use :code:`sudo` even if you have privileges, set
:code:`CH_TEST_DONT_SUDO` to a non-empty string.

The tests use a framework called `Bats <https://github.com/sstephenson/bats>`_
(Bash Automated Testing System). To check location and version of Bats used by
the tests::

  $ make where-bats
  which bats
  /usr/bin/bats
  bats --version
  Bats 0.4.0

Just like for normal use, the Charliecloud test suite is split into build and
run phases, and there is a third phase that runs the examples' test suites.
These phases can be tested independently on different systems.

Testing is coordinated by :code:`make`. The test targets run one or more test
suites. If any test suite has a failure, testing stops with an error message.

The tests need three work directories with a dozen or so GB of available
space, in order to store image tarballs, unpacked image directories, and
permission test fixtures. These are configured with environment variables; for
example::

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


Phases
======

To run all three phases::

  $ make test

We recommend that a build box pass all phases so it can be used to run
containers for testing and development.

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
   ✓ ch-builder2tar obspy
   ✓ docker pull dockerpull
   ✓ ch-builder2tar dockerpull
   ✓ nothing unexpected in tarball directory

  41 tests, 0 failures

Note that this phase is much faster with a hot Docker cache.

To refresh the images, you sometimes need to clear the Docker cache. You can
do this with :code:`make clean-docker`. This requires sudo privileges and
deletes all Docker containers and images, whether or not they are related to
the Charliecloud test suite.

Run
---

The run tests require the contents of :code:`$CH_TEST_TARDIR` produced by a
successful build test. Copy this directory to the run system.

Additionally, the user running the tests needs to be a member of at least 2
groups.

File permission enforcement is tested against specially constructed fixture
directories. These should include every meaningful mounted filesystem, and
they cannot be shared between different users. To create them::

  $ for d in $CH_TEST_PERMDIRS; do sudo ./make-perms-test $d $USER nobody; done

To skip testing file permissions (e.g., if you don't have root), set
:code:`$CH_TEST_PERMDIRS` to :code:`skip`.

To run these tests::

  $ make test-run

Examples
--------

Some of the examples include test suites of their own. Charliecloud runs those
test suites, using a Slurm allocation if one is available or a single node
(localhost) if not.

These require that the run tests have been completed successfully.

Note that single tests from the Charliecloud perspective can include entire
test suites from the example's perspective, so be patient.

To run these tests::

  $ make test-test


Scope (speed vs. thoroughness)
==============================

Generally
---------

The test suite can be abbreviated or extended by setting the environment
variable :code:`CH_TEST_SCOPE`. The valid values are:

:code:`quick`
  This tests the most important subset of Charliecloud functionality. With a
  hot Docker cache, :code:`make test` should finish in under 30 seconds. It's
  handy for development.

  **Note:** The :code:`quick` scope uses the results of a prior successful
  completion of the :code:`standard` scope.

:code:`standard`
  This adds testing of the remaining Charliecloud functionality and a
  selection of the more important examples. It should finish in 5–10 minutes.

  This is the default if :code:`CH_TEST_SCOPE` is unset.

:code:`full`
  Run all available tests. It can take 30–60 minutes or more.

For example, to run the build tests in quick mode, say::

  $ CH_TEST_SCOPE=quick make test-build

Running a single test group
---------------------------

For focused testing, you can run a single :code:`.bats` file directly with
Bats. These are found at the following locations::

  test
  test/run
  examples/*/*/test.bats

First, check which :code:`bats` executable the test suite is using::

  $ make where-bats
  which bats
  /usr/local/src/charliecloud/test/bats/bin/bats
  bats --version
  Bats 0.4.0

Then, use that :code:`bats` to run the file you're interested in. For example,
you can test the :code:`mpihello` example with::

  $ cd examples/mpi/mpihello
  $ /usr/local/src/charliecloud/test/bats/bin/bats test.bats
   ✓ mpihello/serial
   ✓ mpihello/guest starts ranks
   ✓ mpihello/host starts ranks

  3 tests, 0 failures

You will typically need to first make the image available in the appropriate
location, either with successful :code:`build` and :code:`run` tests or
manually building and unpacking it.
