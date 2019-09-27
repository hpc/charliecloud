Synopsis
========

::

  $ ch-test PHASE [ARGS]

Description
===========

Run the Charliecloud test suite.


Phases:

  :code:`build`
    Test image building and associated functionality with your preferred
    builder.

  :code:`run`
    Test charliecloud functionality using images produced by your builder.

    This phase requires contents in tarball directory (:code:`--tar-dir DIR`)
    produced by a successful :code:`build` phase execution. Copy this tarball
    directory to the run system if it differs from your build system.

  :code:`examples`
    Test the example application images.

    This phase requires contents in image directory (:code:`--img-dir`) produced
    by a successful :code:`run` phase execution.

    These tests are run using a slurm allocation if one is available or single
    node (localhost) if not.

  :code:`mk-perm-dirs`
    Create a series of files and test fixtures used to test file
    permission enforcement.

    Requires :code:`--sudo` and :code:`--perm-dirs DIR` arguments

  :code:`rm-perm-dirs`
    Remove test fixtures for kernel file permission enforcement.

    Requires :code:`--sudo` and :code:`--perm-dirs DIR` arguments.

  :code:`clean`
    Delete test artifacts in :code:`--img-dir DIR` and :code:`--tar-dir DIR`.

.. note::
    If no phase is specified, :code:`ch-test` will execute the following
    phases in order: :code:`build`, :code:`run`, and :code:`examples`

Optional arguments:

  :code:`-b`, :code:`--builder`
    Specify prefered image builder. Default: :code:`$CH_BUILDER`.

  :code:`--dry-run`
    Print test suite phase details without executing.

  :code:`-h`, :code:`--help`
    Print usage.

  :code:`--img-dir DIR`
    Store unpacked images from the :code:`run` phase in directory :code:`DIR`.
    Defaults: :code:`$CH_TEST_IMGDIR` if set, or :code:`/var/tmp/img`.

  :code:`--perm-dir DIR`
    Specify directory :code:`DIR` for file permission enforcement testing.
    Requires :code:`--sudo`. Default: :code:`CH_TEST_PERMDIRS` if set, or
    :code:`skip`.

    :code:`--perm-dir` can be set multiple times to create testing fixtures
    in multiple places.

  :code:`-s`, :code:`--scope [quick|standard|full]`
    Run tests with given scope (speed vs. thoroughness). Default:
    :code:`standard`.

    * :code:`quick` - Test the most important subset of Charliecloud
      functionality. Handy for development. Estimated completion time (clean
      image cache): 60-120 seconds.

    * :code:`standard` - Test all Charliecloud functionality and a selection of
      more important examples. Estimated completion time (clean image cache):
      5-10 minutes.

    * :code:`full` - Run all available tests and examples. Estimated
      completion time (clean image cache): 1-2 hours.

  :code:`--sudo`
    Run an extra set of tests, e.g., file permission enforcement tests,
    privilege escalation tests, etc. Requires :code:`sudo` capabilities.

  :code:`--tar-dir DIR`
    Store image tarballs from :code:`build` phase in directory :code:`DIR`.
    Defaults: :code:`$CH_TEST_TARDIR` if set, or :code:`/var/tmp/tar`.

Storage
=======

The test suite requires a few tens of GB of storage for test fixtures:

* Builder storage (e.g., layer cache). This goes wherever the builder puts it.

* Compressed image directory, i.e., :code:`--tar-dir DIR`.

* Unpackaged image directory, i.e., :code:`--img-dir DIR`.

* File permission enforcement fixtures, i.e., :code:`--perm-dirs DIR`.

All of these directories are created if they don't exist.

Exit status
===========

Zero if the tests passed; non-zero if they failed. For phase :code:`clean`,
zero if everything was deleted correctly, non-zero otherwise.

Single system examples
======================

Vanilla (single system):

::

    $ ch-test


With Kernel permission enforcement tests (single system):

::

    $ ch-test mk-perm-dirs --sudo --perm-dirs /tmp/perm_tests
    [...]
    $ ch-test --sudo --perm-dirs /var/tmp
    [...]


Multi-system example
====================

The following example assumes multiple systems, i.e., separate build and
runtime environments.

Build system:

::

    $ ch-test build --scope full
    [...]
    $ scp 0.12.tar.gz ${USER}@hostname.domain:/scratch/

Run system:

::

    $ cd /scratch; tar xf 0.12.tar.gz
    $ ch-test run --tar-dir /scratch/tar --scope full
    [...]
