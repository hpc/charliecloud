Installation
************

This section describes how to build and install Charliecloud. For some
distributions, this can be done using your package manager; otherwise, both
normal users and admins can build and install it manually.

.. contents::
   :depth: 2
   :local:


Dependencies
============

Charliecloud is a simple system with limited dependencies. If your system
meets these prerequisites but Charliecloud doesn't work, please report that as
a bug.

Note that we do not rigorously track dependency versions. We update the
versions stated below as we encounter problems, but they are not tight bounds
and may be out of date.

Supported architectures
-----------------------

Charliecloud should work on any architecture supported by the Linux kernel,
and we have run Charliecloud containers on x86-64, ARM, and Power. However, it
is currently tested only on x86_64 and ARM.

Most container build software is also fairly portable; e.g., see `Docker's
supported platforms <https://docs.docker.com/install/#supported-platforms>`_.

Run time
--------

Systems used for running images need:

* Recent Linux kernel with user namespaces enabled. We recommend version 4.4
  or higher.

* C11 compiler and standard library
  
* GNU automake and autoconf

* POSIX.1-2017 shell and utilities

The SquashFS workflow requires FUSE and `Squashfuse
<https://github.com/vasi/squashfus>`_. Note that distribution packages of
Squashfuse often provide only the "high level" executables; the "low level"
executables have better performance. These can be installed from source on any
distribution.

Some distributions need configuration changes to enable user namespaces. For
example:

* Debian Stretch `needs sysctl <https://superuser.com/a/1122977>`_
  :code:`kernel.unprivileged_userns_clone=1`.

* RHEL/CentOS 7.4 and 7.5 need both a `kernel command line option and a sysctl <https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_atomic_host/7/html-single/getting_started_with_containers/#user_namespaces_options>`_.
  *Important note:* Docker does not work with user namespaces, so skip step 4
  of the Red Hat instructions, i.e., don't add :code:`--userns-remap` to the
  Docker configuration (see `issue #97
  <https://github.com/hpc/charliecloud/issues/97>`_).

Build time
----------

Systems used for building images need the run-time dependencies, plus
something to actually build the images. Sub-sections list Charliecloud
dependencies for each builder; see also the builders' documentation.

All builders require internet access (e.g., for public Docker Hub) or
configuration for a local image repository (e.g., a private Docker Hub).

Additional dependencies for specific components:

* To create SquashFS image files: :code:`squashfs-tools`

* :code:`ch-build2dir`: Bash 4.1+

Buildah (privileged or unprivileged)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Charliecloud uses Buildah's "rootless" mode and ignore-chown-errors storage 
configuration to acheive a fully unprivileged workflow. If an image with 
multpile user mappings is pulled using this method, all file permissions will
be remapped to a single user (root). This requires Buildah v1.10.1 or newer. 

For a privileged workflow, Charliecloud can also use Buildah with setuid
helpers :code:`newuidmap` and :code:`newgidmap`. This will not remap the file 
permissions to root.

.. note::

   To configure Buildah in rootless mode, which is what Charliecloud uses,
   make sure your config files are in :code:`~/.config/containers` and they
   are correct. Particularly if your system also has configuration in
   :code:`/etc/containers`, problems can be very hard to diagnose.

..
   For example, with different mistakes in
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

:code:`ch-grow` (unprivileged)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This is our internal unprivileged image builder and requires:

* `skopeo <https://github.com/containers/skopeo>`_
* `umoci <https://github.com/openSUSE/umoci>`_
* Python module :code:`lark`
  (`lark-parser <https://pypi.org/project/lark-parser/>`_ on PyPI)

Docker (privileged)
~~~~~~~~~~~~~~~~~~~

Our wrapper scripts for Docker expect to run the :code:`docker` command under
:code:`sudo` and need Docker 17.03+ and :code:`mktemp(1)`. Older versions of
Docker may work but are untested. We know that 1.7.1 does not work.

Test suite
----------

To run the test suite, you also need:

* `Bats <https://github.com/sstephenson/bats>`_ 0.4.0 (`Bats-core
  <https://github.com/bats-core/bats-core>`_, a newer fork of Bats, is
  untested)
* Bash 4.1+, for Bats and to make programming the tests tractable
* Python 2.7 or 3.4+, for building some of the tests
* Wget, to download stuff for some of the test images
* root access via :code:`sudo` (optional), to test filesystem permissions enforcement

Image building software tested, with varying levels of thoroughness:

* Shell scripts with various manual bootstrap and :code:`ch-run`
* Docker
* `Buildah <https://github.com/containers/buildah>`_
* `skopeo <https://github.com/containers/skopeo>`_ and
  `umoci <https://github.com/openSUSE/umoci>`_


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

openSUSE and SUSE
-----------------

Charliecloud is included in openSUSE Tumbleweed.
For SUSE Linux Enterprise users, it's available via
`SUSE Package Hub
<https://packagehub.suse.com/packages/charliecloud/>`_.

.. list-table::
   :widths: auto

   * - Package name
     - :code:`charliecloud`, :code:`charliecloud-doc` and :code:`charliecloud-examples`
   * - Maintainers
     - Ana Guerrero Lopez (:code:`aguerrero@suse.com`)
       and Christian Goll (:code:`cgoll@suse.com`)
   * - Bug reports to
     - `openSUSE Bugzilla <https://en.opensuse.org/openSUSE:Submitting_bug_reports>`_
   * - Packaging source code
     - `openSUSE Build Service <https://build.opensuse.org/package/show/network:cluster/charliecloud>`_


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

NixOS
-----

Charliecloud is available as a Nix package; see `See Nixpkgs repository
<https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/virtualization/charliecloud>`_.

.. list-table::
   :widths: auto

   * - Distribution versions
     - *Unstable* channel
   * - Maintainers
     - Bruno Bzeznik (:code:`Bruno@bzizou.net`)
   * - Bug reports to
     - Nixos's GitHub issue tracker
   * - Packaging source code
     - Nixpkgs repository <https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/virtualization/charliecloud/default.nix>`_.

Manual build and install
========================

Download
--------

See our GitHub project: https://github.com/hpc/charliecloud

The recommended download method is :code:`git clone --recursive`.

Build
-----

To build, use::

  $ ./configure
  $ make

  ./confgure has several options that can be specified at build time
  --enable-docs (Build the docs)
  --enable-tests (Build the test suite)
  --disable-docker (Disable docker support)
  --disable-chgrow (Disable ch-grow support)
  --disable-buildah (Disable buildah support) 

To build the documentation, see :ref:`the contributor's guide <doc-build>`.

Install (optional)
------------------

You can run Charliecloud from the source directory, and it's recommended you
at least run the test suite before installation to establish that your system
will work.

To install (FHS-compliant)::

  $ make install --prefix=/foo/bar

If building a package for charliecloud, use :DISTDIR to specify the working directory

  $ make install --prefix=/foo/bar --DISTDIR=/foo/package_location

Note that :code:`prefix` is required. It does not default to
:code:`/usr/local` like many packages.


.. include:: ./docker_tips.rst
