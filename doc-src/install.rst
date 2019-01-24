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
   to tickle. There is a patch available from Cray for CLE6.0 UP04 and UP05.
   The fix is mainlined into Cray CLE6.0 UP06, released in March 2018. Versions
   of Cray CLE6.0 prior to UP04 are unpatched and affected by the bug.
   Non-Cray build boxes and others at the same site can still use
   the master branch.

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

* Recent Linux kernel with :code:`CONFIG_USER_NS=y`. We recommend version 4.4
  or higher.

* C compiler and standard library

* POSIX shell and utilities

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
* Python 2.6+
* `Bats <https://github.com/sstephenson/bats>`_ 0.4.0
* wget

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

To build, simply::

  $ make

To build the documentation, see :ref:`the contributor's guide <doc-build>`.

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
