Installation
************

This section describes how to build and install Charliecloud. For some
distributions, this can be done using your package manager; otherwise, both
normal users and admins can build and install it manually.

.. contents::
   :depth: 2
   :local:


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
