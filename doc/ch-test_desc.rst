Synopsis
========

::

  $ ch-test [PHASE] [--scope SCOPE] [--pack-fmt FMT] [ARGS]


Description
===========

Charliecloud comes with a comprehensive test suite that exercises the
container workflow itself as well as a few example applications.
:code:`ch-test` coordinates running the test suite.

While the CLI has lots of options, the defaults are reasonable, and bare
:code:`ch-test` will give useful results in a few minutes on single-node,
internet-connected systems with a few GB available in :code:`/var/tmp`.

The test suite requires a few GB (standard scope) or tens of GB (full scope)
of storage for test fixtures:

* *Builder storage* (e.g., layer cache). This goes wherever the builder puts
  it.

* *Packed images directory*: image tarballs or SquashFS files.

* *Unpacked images directory*. Images are unpacked into and then run from
  here.

* *Filesystem permissions* directories. These are used to test that the
  kernel is enforcing permissions correctly. Note that this exercises the
  kernel, not Charliecloud, and can be omitted from routine Charliecloud
  testing.

The first three are created when needed if they don't exist, while the
filesystem permissions fixtures must be created manually, in order to
accommodate configurations where sudo is not available via the same login path
used for running tests.

The packed and unpacked image directories specified for testing are volatile.
The contents of these directories are deleted before the build and run phases,
respectively.

In all four cases, when creating directories, only the final path component is
created. Parent directories must already exist, i.e., :code:`ch-test` uses the
behavior of :code:`mkdir` rather than :code:`mkdir -p`.

Some of the tests exercise parallel functionality. If :code:`ch-test` is run
on a single node, multiple cores will be used; if in a Slurm allocation,
multiple nodes too.

The subset of tests to run mostly splits along two key dimensions. The *phase*
is which parts of the workflow to run. Different parts of the workflow can be
tested on different systems by copying the necessary artifacts between them,
e.g. by building images on one system and running them on another. The *scope*
allows trading off thoroughness versus time.

:code:`PHASE` must be one of the following:

  :code:`build`
    Image building and associated functionality, with the selected builder.

  :code:`run`
    Running containers and associated functionality. This requires a packed
    images directory produced by a successful :code:`build` phase, which can
    be copied from the build system if it's not also the run system.

  :code:`examples`
    Example applications. Requires an unpacked images directory produced by a
    successful :code:`run` phase.

  :code:`all`
    Execute phases :code:`build`, :code:`run`, and :code:`examples`, in that
    order.

  :code:`mk-perm-dirs`
    Create the filesystem permissions directories. Requires
    :code:`--perm-dirs`.

  :code:`clean`
    Delete automatically-generated test files, and packed and unpacked image
    directories.

  :code:`rm-perm-dirs`
    Remove the filesystem permissions directories. Requires
    :code:`--perm-dirs`.

  :code:`-f`, :code:`--file FILE[:TEST]`
    Run the tests in the given file only, which can be an arbitrary
    :code:`.bats` file, except for :code:`test.bats` under :code:`examples`,
    where you must specify the corresponding Dockerfile or :code:`Build` file
    instead. This is somewhat brittle and typically used for development or
    debugging. For example, it does not check whether the pre-requisites of
    whatever is in the file are satisfied. Often running :code:`build` and
    :code:`run` first is sufficient, but this varies.

    If :code:`TEST` is also given, then run only tests with name containing
    that string, skipping the others. The separator is a literal colon. If the
    string contains shell metacharacters such as space, you'll need to quote
    the argument to protect it from the shell.

Scope is specified with:

  :code:`-s`, :code:`--scope SCOPE`
    :code:`SCOPE` must be one of the following:

    * :code:`quick`: Most important subset of workflow. Handy for development.

    * :code:`standard`: All tested workflow functionality and a selection of
      more important examples. (Default.)

    * :code:`full`: All available tests, including all examples.

Image format is specified with:

  :code:`--pack-fmt FMT`
    :code:`FMT` must be one of the following:

    * :code:`squash-mount` or 🐘: SquashFS archive, run directly from the
      archive using :code:`ch-run`'s internal SquashFUSE functionality. In
      this mode, tests that require writing to the image are skipped.

    * :code:`tar-unpack` or 📠: Tarball, and the images are unpacked before
      running.

    * :code:`squash-unpack` or 🎃: SquashFS, and the images are unpacked
      before running.

    Default: :code:`$CH_TEST_PACK_FMT` if set. Otherwise, if
    :code:`mksquashfs(1)` is available and :code:`ch-run` was built with
    :code:`libsquashfuse` support, then :code:`squash-mount`, else
    :code:`tar-unpack`.

Additional arguments:

  :code:`-b`, :code:`--builder BUILDER`
    Image builder to use. Default: :code:`$CH_TEST_BUILDER` if set, otherwise
    :code:`ch-image`.

  :code:`--dry-run`
    Print summary of what would be tested and then exit.

  :code:`-h`, :code:`--help`
    Print usage and then exit.

  :code:`--img-dir DIR`
    Set unpacked images directory to :code:`DIR`. In a multi-node allocation,
    this directory may not be shared between nodes. Default:
    :code:`$CH_TEST_IMGDIR` if set; otherwise :code:`/var/tmp/img`.

  :code:`--lustre DIR`
    Use :code:`DIR` for run-phase Lustre tests. Default:
    :code:`CH_TEST_LUSTREDIR` if set; otherwise skip them.

    The tests will create, populate, and delete a new subdirectory under
    :code:`DIR`, leaving everything else in :code:`DIR` untouched.

  :code:`--pack-dir DIR`
    Set packed images directory to :code:`DIR`. Default:
    :code:`$CH_TEST_TARDIR` if set; otherwise :code:`/var/tmp/pack`.

  :code:`--pedantic (yes|no)`
    Some tests require configurations that are very specific (e.g., being a
    member of at least two groups) or unusual (e.g., sudo to a non-root
    group). If :code:`yes`, then fail if the requirement is not met; if
    :code:`no`, then skip. The default is :code:`yes` for CI environments or
    people listed in :code:`README.md`, :code:`no` otherwise.

    If :code:`yes` and sudo seems to be available, implies :code:`--sudo`.

  :code:`--perm-dir DIR`
    Add :code:`DIR` to filesystem permission fixture directories; can be
    specified multiple times. We recommend one such directory per mounted
    filesystem type whose kernel module you do not trust; e.g., you probably
    don't need to test your :code:`tmpfs`\ es, but out-of-tree filesystems very
    likely need this.

    Implies :code:`--sudo`. Default: :code:`CH_TEST_PERMDIRS` if set;
    otherwise skip the filesystem permissions tests.

  :code:`--sudo`
    Enable things that require sudo, such as certain privilege escalation
    tests and creating/removing the filesystem permissions fixtures. Requires
    generic :code:`sudo` capabilities. Note that the Docker builder uses
    :code:`sudo docker` even without this option.


Exit status
===========

Zero if all tests passed; non-zero if any failed. For setup and teardown
phases, zero if everything was created or deleted correctly, non-zero
otherwise.


Bugs
====

Bats will wait until all descendant processes finish before exiting, so if you
get into a failure mode where a test sequence doesn't clean up all its
processes, :code:`ch-test` will hang.


Examples
========

Many systems can simply use the defaults. To run the :code:`build`,
:code:`run`, and :code:`examples` phases on a single system, without the
filesystem permissions tests::

  $ ch-test
  ch-test version 0.12

  ch-run: 0.12 /usr/local/bin/ch-run
  bats:   0.4.0 /usr/bin/bats
  tests:  /usr/local/libexec/charliecloud/test

  phase:                build run examples
  scope:                standard (default)
  builder:              docker (default)
  use generic sudo:     no (default)
  unpacked images dir:  /var/tmp/img (default)
  packed images dir:    /var/tmp/tar (default)
  fs permissions dirs:  skip (default)

  checking namespaces ...
  ok

  checking builder ...
  found: /usr/bin/docker 19.03.2

  bats build.bats build_auto.bats build_post.bats
   ✓ documentation seems sane
   ✓ version number seems sane
  [...]
  All tests passed.

The next example is for a more complex setup like you might find in HPC
centers:

  * Non-default fixture directories.
  * Non-default scope.
  * Different build and run systems.
  * Run the filesystem permissions tests.

Output has been omitted.

::

   (mybox)$ ssh hpc-admin
   (hpc-admin)$ ch-test mk-perm-dirs --perm-dir /scratch/$USER/perms \
                                     --perm-dir /home/$USER/perms
   (hpc-admin)$ exit
   (mybox)$ ch-test build --scope full
   (mybox)$ scp -r /var/tmp/pack hpc:/scratch/$USER/pack
   (mybox)$ ssh hpc
   (hpc)$ salloc -N2
   (cn001)$ export CH_TEST_TARDIR=/scratch/$USER/pack
   (cn001)$ export CH_TEST_IMGDIR=/local/tmp
   (cn001)$ export CH_TEST_PERMDIRS="/scratch/$USER/perms /home/$USER/perms"
   (cn001)$ export CH_TEST_SCOPE=full
   (cn001)$ ch-test run
   (cn001)$ ch-test examples


..  LocalWords:  fmt img LUSTREDIR
