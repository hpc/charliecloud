Installing
**********

This section describes what you need to install Charliecloud and how to do so.

Note that installing and using Charliecloud can be done as a normal user with
no elevated privileges, provided that user namespaces have been enabled.

.. contents::
   :depth: 2
   :local:


Build and install from source
=============================

Using release tarball
---------------------

We provide `tarballs <https://github.com/hpc/charliecloud/releases>`_ with a
fairly standard :code:`configure` script. Thus, build and install can be as
simple as::

  $ ./configure
  $ make
  $ sudo make install

If you don't have sudo, you can:

  * Run Charliecloud directly from the build directory; add
    :code:`$BUILD_DIR/bin` to your :code:`$PATH` and you are good to go,
    without :code:`make install`.

  * Install in a prefix you have write access to, e.g. in your home directory
    with :code:`./configure --prefix=~`.

:code:`configure` will provide a detailed report on what will be built and
installed, along with what dependencies are present and missing.

From Git checkout
-----------------

If you obtain the source code with Git, you must build :code:`configure` and
friends yourself. To do so, you will need the following. The versions in most
common distributions should be sufficient.

  * Automake
  * Autoconf
  * Python's :code:`pip3` package installer and its :code:`wheel` extension

Create :code:`configure` with::

  $ ./autogen.sh

This script has a few options; see its :code:`--help`.

Note that Charliecloud disables Automake's "maintainer mode" by default, so
the build system (Makefiles, :code:`configure`, etc.) will never automatically
be rebuilt. You must run :code:`autogen.sh` manually if you need this. You can
also re-enable maintainer mode with :code:`configure` if you like, though this
is not a tested configuration.

:code:`configure` options
-------------------------

Charliecloud's :code:`configure` has the following options in addition to the
standard ones.

Feature selection: :code:`--disable-FOO`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

By default, all features that can be built will be built and installed. You
can exclude some features with:

  ========================== =======================================================
  option                     don't build/install
  ========================== =======================================================
  :code:`--disable-ch-image` :code:`ch-image` unprivileged builder & image manager
  :code:`--disable-html`     HTML documentation
  :code:`--disable-man`      man pages
  :code:`--disable-syslog`   logging to syslog (see individual man pages)
  :code:`--disable-tests`    test suite
  ========================== =======================================================

You can also say :code:`--enable-FOO` to fail the build if :code:`FOO` can't
be built.

Dependency selection: :code:`--with-FOO`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Some dependencies can be specified as follows. Note only some of these support
:code:`--with-FOO=no`, as listed.

:code:`--with-libsquashfuse={yes,no,PATH}`
  Whether to link with :code:`libsquashfuse`. Options:

  * If not specified: Look for :code:`libsquashfuse` in standard install
    locations and link with it if found. Otherwise disable internal SquashFS
    mount, with no warning or error.

  * :code:`yes`: Look for :code:`libsquashfuse` in standard locations and link
    with it if found; otherwise, error.

  * :code:`no`: Disable :code:`libsquashfuse` linking and internal SquashFS
    mounting, even if it's installed.

  * Path to :code:`libsquashfuse` install prefix: Link with
    :code:`libsquashfuse` found there, or error if not found, and add it to
    :code:`ch-run`'s RPATH. (Note this argument is *not* the directory
    containing the shared library or header file.)

  **Note:** A very specific version and configuration of SquashFUSE is
  required. See below for details.

:code:`--with-python=SHEBANG`
  Shebang line to use for Python scripts. Default:
  :code:`/usr/bin/env python3`.

:code:`--with-sphinx-build=PATH`
  Path to :code:`sphinx-build` executable. Default: the :code:`sphinx-build`
  found first in :code:`$PATH`.

:code:`--with-sphinx-python=PATH`
  Path to Python used by :code:`sphinx-build`. Default: shebang of
  :code:`sphinx-build`.

Less strict build: :code:`--enable-buggy-build`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

*Please do not use this option routinely, as that hides bugs that we cannot
find otherwise.*

By default, Charliecloud builds with :code:`CFLAGS` including :code:`-Wall
-Werror`. The principle here is that we prefer diagnostics that are as noisy
as practical, so that problems are identified early and we can fix them. We
prefer :code:`-Werror` unless there is a specific reason to turn it off. For
example, this approach identified a buggy :code:`configure` test (`issue #798
<https://github.com/hpc/charliecloud/issues/798>`_).

Many others recommend the opposite. For example, Gentoo's "`Common mistakes
<https://devmanual.gentoo.org/ebuild-writing/common-mistakes/index.html>`_"
guide advises against :code:`-Werror` because it causes breakage that is
"random" and "without purpose". There is a well-known `blog post
<https://flameeyes.blog/2009/02/25/future-proof-your-code-dont-use-werror/>`_
from Flameeyes that recommends :code:`-Werror` be off by default and used by
developers and testers only.

In our opinion, for Charliecloud, these warnings are most likely the result of
real bugs and shouldn't be hidden (i.e., they are neither random nor without
purpose). Our code should have no warnings, regardless of compiler, and any
spurious warnings should be silenced individually. We do not have the
resources to test with a wide variety of compilers, so enabling
:code:`-Werror` only for development and testing, as recommended by others,
means that we miss potentially important diagnostics — people typically do not
pay attention to warnings, only errors.

That said, we recognize that packagers and end users just want to build the
code with a minimum of hassle. Thus, we provide the :code:`configure` flag:

:code:`--enable-buggy-build`
  Remove :code:`-Werror` from :code:`CFLAGS` when building.

Don't hesitate to use it. But if you do, we would very much appreciate if you:

  1. File a bug explaining why! We'll fix it.
  2. Remove it from your package or procedure once we fix that bug.

Disable bundled Lark package: :code:`--disable-bundled-lark`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

*This option is minimally supported and not recommended. Use only if you
really know what you are doing.*

Charliecloud uses the Python package `Lark
<https://lark-parser.readthedocs.io/en/latest/>`_ for parsing Dockerfiles and
image references. Because this package is developed rapidly, and recent
versions have important features and bug fixes not yet available in common
distributions, we bundle the package with Charliecloud.

If you prefer a separately-installed Lark, either via system packages or
:code:`pip`, you can use :code:`./configure --disable-bundled-lark`. This
excludes the bundled Lark from being installed or placed in :code:`make dist`
tarballs. It *does not* remove the bundled Lark from the source directory; if
you run from the source directory (i.e., without installing), the bundled Lark
will be used if present regardless of this option.

Bundled Lark is included in the tarballs we distribute. You can remove it and
re-build :code:`configure` with :code:`./autogen.sh --rm-lark --no-lark`. If
you are starting from a Git checkout, bundled Lark is installed by default by
:code:`./autogen.sh`, but you can prevent this with :code:`./autogen.sh
--no-lark`.

The main use case for these options is to support package maintainers. If this
is you and does not meet your needs, please get in touch with us and we will
help.

Install with package manager
============================

Charliecloud is also available using a variety of distribution and third-party
package managers.

Maintained by us:

  * `Spack
    <https://spack.readthedocs.io/en/latest/package_list.html#charliecloud>`_;
    install with :code:`+builder` to get :code:`ch-image`.
  * `Fedora/EPEL <https://bodhi.fedoraproject.org/updates/?search=charliecloud>`_;
    check for available versions with :code:`{yum,dnf} list charliecloud`.

Maintained by others:

  * `Debian <https://packages.debian.org/source/charliecloud>`_
  * `Gentoo <https://packages.gentoo.org/packages/sys-cluster/charliecloud>`_
  * `NixOS <https://github.com/NixOS/nixpkgs/tree/master/pkgs/applications/virtualization/charliecloud>`_
  * `SUSE <https://packagehub.suse.com/packages/charliecloud/>`_ and `openSUSE <https://build.opensuse.org/package/show/network:cluster/charliecloud>`_

Note that Charliecloud development moves quickly, so double-check that
packages have the version and features you need.

Pull requests and other collaboration to improve the packaging situation are
particularly welcome!


Dependencies
============

Charliecloud's philosophy on dependencies is that they should be (1) minimal
and (2) granular. For any given feature, we try to implement it with the
minimum set of dependencies, and in any given environment, we try to make the
maximum set of features available.

This section documents Charliecloud's dependencies in detail. Do you need to
read it? If you are installing Charliecloud on the same system where it will
be used, probably not. :code:`configure` will issue a report saying what will
and won't work. Otherwise, it may be useful to gain an understanding of what
to expect when deploying Charliecloud.

Note that we do not rigorously track dependency versions. We update the
minimum versions stated below as we encounter problems, but they are not tight
bounds and may be out of date. It is worth trying even if your version is
documented to be too old. Please let us know any success or failure reports.

Finally, the run-time dependencies are lazy; specific features just try to use
their dependencies and fail if there's a problem, hopefully with a useful
error message. In other words, there's no version checking or whatnot that
will keep you from using a feature unless it truly doesn't work in your
environment.

User namespaces
---------------

Charliecloud's fundamental principle of a workflow that is fully unprivileged
end-to-end requires unprivileged `user namespaces
<https://lwn.net/Articles/531114/>`_. In order to enable them, you need a
vaguely recent Linux kernel with the feature compiled in and active.

Some distributions need configuration changes. For example:

* Debian Stretch `needs sysctl <https://superuser.com/a/1122977>`_
  :code:`kernel.unprivileged_userns_clone=1`.

* RHEL/CentOS 7.4 and 7.5 need both a `kernel command line option and a sysctl
  <https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_atomic_host/7/html-single/getting_started_with_containers/#user_namespaces_options>`_.
  RHEL/CentOS 7.6 and up need only the sysctl. Note that Docker does not work
  with user namespaces, so skip step 4 of the Red Hat instructions, i.e.,
  don't add :code:`--userns-remap` to the Docker configuration (see `issue #97
  <https://github.com/hpc/charliecloud/issues/97>`_).

Note: User namespaces `always fail in a chroot
<http://man7.org/linux/man-pages/man2/unshare.2.html>`_ with :code:`EPERM`. If
:code:`configure` detects that it's in a chroot, it will print a warning in
its report. One common scenario where this comes up is packaging, where builds
often happen in a chroot. However, like all the run-time :code:`configure`
tests, this is informational only and does not affect the build.

Supported architectures
-----------------------

Charliecloud should work on any architecture supported by the Linux kernel,
and we have run Charliecloud containers on x86-64, ARM, and Power. However, it
is currently tested only on x86_64 and ARM.

Most builders are also fairly portable; e.g., see `Docker's supported
platforms <https://docs.docker.com/install/#supported-platforms>`_.

libc
----

We want Charliecloud to work with any C99/POSIX libc, though it is only tested
with `glibc <https://www.gnu.org/software/libc/>`_ and `musl
<https://musl.libc.org/>`_, and other libc's are very likely to have problems.
(Please report these bugs!) Non-glibc libc's will currently need a `standalone
libargp <https://github.com/ericonr/argp-standalone>`_ (see issue `#1260
<https://github.com/hpc/charliecloud/issues/1260>`_).

Details by feature
------------------

This section is a comprehensive listing of the specific dependencies and
versions by feature group. It is auto-generated from the definitive source,
:code:`configure.ac`.

Listed versions are minimums, with the caveats above. Everything needs a POSIX
shell and utilities.

The next section contains notes about some of the dependencies.

.. include:: _deps.rst

Notes on specific dependencies
------------------------------

This section describes additional details we have learned about some of the
dependencies. Note that most of these are optional. It is in alphabetical
order by dependency.

Bash
~~~~

When Bash is needed, it's because:

  * Shell scripting is a lot easier in Bash than POSIX shell, so we use it for
    scripts applicable in contexts where it's very likely Bash is already
    available.

  * It is required by our testing framework, Bats.

Bats
~~~~

Bats ("Bash Automated Testing System") is a test framework for tests written
as Bash shell scripts. The test suite uses `Bats-core <https://github.com/bats-core/bats-core>`_.

Buildah
~~~~~~~

Charliecloud uses Buildah's "rootless" mode and :code:`ignore-chown-errors`
storage configuration for a fully unprivileged workflow with no sudo and no
setuid binaries. Note that in this mode, images in Buildah internal storage
will have all user and group ownership flattened to UID/GID 0.

If you prefer a privileged workflow, Charliecloud can also use Buildah with
setuid helpers :code:`newuidmap` and :code:`newgidmap`. This will not remap
ownership.

To configure Buildah in rootless mode, make sure your config files are in
:code:`~/.config/containers` and they are correct. Particularly if your system
also has configuration in :code:`/etc/containers`, problems can be very hard
to diagnose.

.. For example, with different mistakes in
   :code:`~/.config/containers/storage.conf` and
   :code:`/etc/containers/storage.conf` present or absent, and all in rootless
   mode, we have seen various combinations of:

     * error messages about configuration
     * error messages about :code:`lchown`
     * using :code:`storage.conf` from :code:`/etc/containers` instead of
       :code:`~/.config/containers`
     * using default config documented for rootless
     * using default config documented for rootful
     * exiting zero
     * exiting non-zero
     * completing the build
     * not completing the build

   We assume this will be straightened out over time, but for the time being,
   if you encounter strange problems with Buildah, check that your config
   resides only in :code:`~/.config/containers` and is correct.

C compiler
~~~~~~~~~~

We test with GCC. Core team members use whatever version comes with their
distribution.

In principle, any C99 compiler should work. Please let us know any success or
failure reports.

Intel :code:`icc` is not supported because it links extra shared libraries
that our test suite can't deal with. See `PR #481
<https://github.com/hpc/charliecloud/pull/481>`_.

image repository access
~~~~~~~~~~~~~~~~~~~~~~~

:code:`FROM` instructions in Dockerfiles and image pushing/pulling require
access to an image repository and configuring the builder for that repository.
Options include:

  * `Docker Hub <https://hub.docker.com>`_, or other public repository such as
    `gitlab.com <https://gitlab.com>`_ or NVIDIA's `NCG container registry
    <https://ngc.nvidia.com>`_.

  * A private Docker-compatible registry, such as a private Docker Hub or
    GitLab instance.

  * Filesystem directory, for builders that support this (e.g.,
    :code:`ch-image`).

Python
~~~~~~

We use Python for scripts that would be really hard to do in Bash, when we
think Python is likely to be available.

ShellCheck
~~~~~~~~~~

`ShellCheck <https://www.shellcheck.net/>`_ is a very thorough and capable
linter for shell scripts. In order to pass the full test suite, all the shell
scripts need to pass ShellCheck.

While it is widely available in distributions, the packaged version is usually
too old. Building from source is tricky because it's a Haskell program, which
isn't a widely available tool chain. Fortunately, the developers provide
pre-compiled `static binaries
<https://github.com/koalaman/shellcheck/releases>`_ on their GitHub page.

Sphinx
~~~~~~

We use Sphinx to build the documentation; the theme is
`sphinx-rtd-theme <https://sphinx-rtd-theme.readthedocs.io/en/stable/>`_.

Minimum versions are listed above. Note that while anything greater than the
minimum should yield readable documentation, we don't test quality with
anything other than what we use to build the website, which is usually but not
always the most recent version available on PyPI.

If you're on Debian Stretch or some version of Ubuntu, installing with
:code:`pip3` will silently install into :code:`~/.local`, leaving the
:code:`sphinx-build` binary in :code:`~/.local/bin`, which is often not on
your path. One workaround (untested) is to run :code:`pip3` as root, which
violates principle of least privilege. A better workaround, assuming you can
write to :code:`/usr/local`, is to add the undocumented and non-standard
:code:`--system` argument to install in :code:`/usr/local` instead. (This
matches previous :code:`pip` behavior.) See Debian bugs `725848
<https://bugs.debian.org/725848>`_ and `820856
<https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=820856>`_.

SquashFS and SquashFUSE
~~~~~~~~~~~~~~~~~~~~~~~

The SquashFS workflow requires `SquashFS Tools
<https://github.com/plougher/squashfs-tools>`_ to create SquashFS archives.

To mount these archives using :code:`ch-run`'s internal code, you need:

1. `libfuse3 <https://github.com/libfuse/libfuse>`_, including:

   * development files, which are probably available in your distribution,
     e.g., :code:`libfuse3-dev`. (Build time only.)

   * The :code:`fusermount3` executable, which often comes in a distro package
     called something like :code:`fuse3`. **This is typically installed
     setuid, but Charliecloud does not need that**; you can :code:`chmod u-s`
     the file or build/install as a normal user.

2. `SquashFUSE <https://github.com/vasi/squashfuse>`_ v0.1.105 or later (we
   need the :code:`libsquashfuse_ll` shared library). This must be installed,
   not linked from its build directory, though it can be installed in a
   non-standard location.

Without these, you can still use a SquashFS workflow but must mount and
unmount the filesystem archives manually. You can do this using the
executables that come with SquashFUSE, and the version requirement is much
less stringent.

.. note:: If :code:`libfuse2` development files are available but those for
   :code:`libfuse3` are not, SquashFUSE will still build and install, but the
   proper components will not be available, so Charliecloud's
   :code:`configure` will say it's not found.

sudo, generic
~~~~~~~~~~~~~

Privilege escalation via sudo is used in the test suite to:

  * Prepare fixture directories for testing filesystem permissions enforcement.
  * Test :code:`ch-run`'s behavior under different ownership scenarios.

(Note that Charliecloud also uses :code:`sudo docker`; see above.)

Wget
~~~~

Wget is used to demonstrate building an image without a builder (the main test
image used to exercise Charliecloud itself).


..  LocalWords:  Werror Flameeyes plougher deps libc's ericonr
