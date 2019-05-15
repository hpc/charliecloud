Synopsis
========

::

  $ ch-test PHASE [ARG ...]

Description
===========

Run the Charliecloud test suite.

For details about the test suite, see:
https://hpc.github.io/charliecloud/test.html

Available phases are the following. Each phase requires successful completion
of the prior phase at the same scope.

  :code:`build`
    Test that images build correctly.

  :code:`run`
    Test that images run correctly. If :code:`sudo` privileges are
    available, also test file system permission enforcement.

  :code:`examples`
    Test that example applications work correctly.

  :code:`all`
    Test all three phases in the order above. (Default.)

Clean-up phase:

  :code:`clean`
    Delete test data in directories :code:`$CH_TEST_TARDIR`,
    :code:`$CH_TEST_IMGDIR`, and :code:`$CH_TEST_PERMDIRS`. Note image builder
    data is not altered or removed.

Other arguments:

  :code:`-b`, :code:`--builder`
    Specify image builder (ch-grow, buildah, or docker).

  :code:`-p`, :code:`--prefix DIR`
    Directory containing image files/directories and other test fixtures for
    relevant variables, e.g., code:`CH_TEST_IMGDIR`, code:`CH_TEST_TARDIR`,
    code:`CH_TEST_PERMDIRS`. Default: :code:`/var/tmp`.

  :code:`-s`, :code:`--scope [quick|standard|full]`
    Run tests with given scope, e.g., :code:`$CH_TEST_SCOPE`. Default:
    :code:`standard`.

  :code:`--no-sudo`
    Run the tests without the use of sudo.

  :code:`--dry-run`
    Print test suite phase details without executing.

.. :note:
  Precedence: arguments > environment variable > default value

Storage
=======

The test suite requires a few tens of GB of storage for test fixtures:

* Builder storage (e.g., layer cache). This goes wherever the builder puts it.

* Image tarballs: :code:`{--prefix}/tar` or :code:`$CH_TEST_TARDIR` if set.

* Image directories: :code:`{--prefix}/dir` or :code:`$CH_TEST_IMGDIR` if set.

* File permission enforcement fixtures: :code:`{--prefix}/perms_test` or
  :code:`$CH_TEST_PERMDIRS` if set. Note file permissions tests require
  :code `sudo`.

All of these directories are created if they don't exist.

Exit status
===========

Zero if the tests passed; non-zero if they failed. For phase :code:`clean`,
zero if everything was deleted correctly, non-zero otherwise.

Example
=======
::
  $ ch-test all --builder ch-grow --scope quick

  CH_TEST_TARDIR        /var/tmp/tar
  CH_TEST_IMGDIR        /var/tmp/img
  CH_TEST_PERMDIRS      /var/tmp /tmp
  CH_TEST_SCOPE         quick
  CH_BUILDER            ch-grow

  test root directory:  /usr/local/libexec/charliecloud-0.11~pre+spackunsafeconfig.68efaeb/test

  checking builder (ch-grow) sanity...

  bats build.bats build_auto.bats build_post.bats
  ✓ create tarball directory if needed
  ✓ documentations build
  ✓ version number seems sane
  ✓ executables seem sane
  [...]
  63 tests, 0 failures, 52 skipped
