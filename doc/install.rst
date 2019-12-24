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
  * Autoconf Archive

Create :code:`configure` with::

  $ ./autogen.sh

:code:`configure` options
-------------------------

Charliecloud's :code:`configure` has the following options in addition to the
standard ones.

By default, all features that can be built will be built and installed. You
can exclude some features with:

  =========================  ====================================
  option                     don't build or install
  =========================  ====================================
  :code:`--disable-html`     HTML documentation
  :code:`--disable-man`      man pages
  :code:`--disable-tests`    test suite
  :code:`--disable-ch-grow`  :code:`ch-grow` unprivileged builder
  =========================  ====================================

You can also say :code:`--enable-FOO` to fail the build if :code:`FOO` can't
be built.

Some dependencies can be specified as follows. Note that :code:`--without-FOO`
is not supported; use the feature selectors above.

:code:`--with-python-shebang`
  Shebang line to use for Python scripts. Default:
  :code:`/usr/bin/env python3`.

:code:`--with-sphinx-build`
  Path to :code:`sphinx-build` executable. Default: the :code:`sphinx-build`
  found first in :code:`$PATH`.


Install with package manager
============================

Charliecloud is also available using a variety of distribution and third-party
package managers.

Maintained by us:

  * Generic RPMs downloadable from our `releases page <https://github.com/hpc/charliecloud/releases>`_.
  * `Spack
    <https://spack.readthedocs.io/en/latest/package_list.html#charliecloud>`_;
    install with :code:`+builder` to get :code:`ch-grow`.
  * `Fedora/EPEL <https://bodhi.fedoraproject.org/updates/?search=charliecloud>`_;
    check for availabile versions with :code:`{yum,dnf} list charliecloud`.

Maintained by others:

  * `Debian <https://packages.debian.org/search?keywords=charliecloud>`_
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
  RHEL/CentOS 7.6 and up need only the sysctl.

  *Note:* Docker does not work with user namespaces, so skip step 4 of the Red
  Hat instructions, i.e., don't add :code:`--userns-remap` to the Docker
  configuration (see `issue #97
  <https://github.com/hpc/charliecloud/issues/97>`_).

Supported architectures
-----------------------

Charliecloud should work on any architecture supported by the Linux kernel,
and we have run Charliecloud containers on x86-64, ARM, and Power. However, it
is currently tested only on x86_64 and ARM.

Most builders are also fairly portable; e.g., see `Docker's supported
platforms <https://docs.docker.com/install/#supported-platforms>`_.

Details by feature
------------------

This section is a comprehensive listing of the specific dependencies and
versions by feature group. It is autogenerated from the definitive source,
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
as Bash shell scripts.

`Upstream Bats <https://github.com/sstephenson/bats>`_ is unmaintained, but
widely available. Both version 0.4.0, which tends to be in distributions, and
upstream master branch (commit 0360811) should work. There is a maintained
fork called `Bats-core <https://github.com/bats-core/bats-core>`_, but the
test suite currently does not pass with it; see `issue #582
<https://github.com/hpc/charliecloud/issues/582>`_. Patches welcome!

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

Docker
~~~~~~

Security implications of Docker
...............................

Because Docker (a) makes installing random crap from the internet really easy
and (b) is easy to deploy insecurely, you should take care. Some of the
implications are below. This list should not be considered comprehensive nor a
substitute for appropriate expertise; adhere to your moral and institutional
responsibilities.

* **Docker equals root.** Anyone who can run the :code:`docker` command or
  interact with the Docker daemon can `trivially escalate to root
  <http://web.archive.org/web/20170614013206/http://www.reventlov.com/advisories/using-the-docker-command-to-root-the-host>`_.
  This is considered a feature.

  For this reason, don't create the :code:`docker` group, as this will allow
  passwordless, unlogged escalation for anyone in the group. Our scripts
  expect to run Docker as :code:`sudo docker`.

  Also, Docker runs container processes as root by default. In addition to
  being poor hygiene, this can be an escalation path, e.g. if you bind-mount
  host directories.

* **Docker alters your network configuration.** To see what it did::

    $ ifconfig    # note docker0 interface
    $ brctl show  # note docker0 bridge
    $ route -n

* **Docker installs services.** If you don't want the Docker service starting
  automatically at boot, e.g.::

    $ systemctl is-enabled docker
    enabled
    $ systemctl disable docker
    $ systemctl is-enabled docker
    disabled

Configuring for a proxy
.......................

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

The second problem is that programs executed during build (:code:`RUN`
instructions) need to know about the proxy as well. This manifests as images
failing to build because they can't download stuff from the internet.

The fix is usually to set the proxy variables in your environment, e.g.::

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
test suite will fail if some but not all of the above variables are set.

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
    :code:`ch-grow`).

"lark-parser" Python package
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

PyPI has two incompatible packages that provide the module :code:`lark`,
"`lark-parser <https://pypi.org/project/lark-parser/>`_" and "lark". You want
"lark-parser".

Python
~~~~~~

We use Python for scripts that would be really hard to do in Bash, when we
think Python is likely to be available.

Skopeo
~~~~~~

Our unprivileged builder :code:`ch-grow` uses `Skopeo
<https://github.com/containers/skopeo/>`_ to interact with remote and local
image repositories.

Sphinx
~~~~~~

We use Sphinx to build the documentation. The minimum version is listed above.
We currently use 1.8 for building what's on the web because there are bugs
problematic for us in 2.x, e.g. `bad spacing in lists
<https://github.com/readthedocs/sphinx_rtd_theme/issues/799>`_.

SquashFS
~~~~~~~~

The SquashFS workflow requires `SquashFS Tools
<https://github.com/plougher/squashfs-tools>`_ and/or `SquashFUSE
<https://github.com/vasi/squashfuse>`_. Note that distribution packages of
SquashFUSE often provide only the "high level" executables; the "low level"
executables have better performance. These can be installed from source on any
distribution.

sudo, generic
~~~~~~~~~~~~~

Privilege escalation via sudo is used in the test suite to:

  * Prepare fixture directories for testing filesystem permissions enforcement.
  * Test :code:`ch-run`'s behavior under different ownership scenarios.

(Note that Charliecloud also uses :code:`sudo docker`; see above.)

umoci
~~~~~

Our unprivileged builder :code:`ch-grow` uses `umoci <https://umo.ci/>`_ to
manipulate images during the image build process.

Wget
~~~~

Wget is used to demonstrate building an image without a builder (the main test
image used to exercise Charliecloud itself).


Pre-installed virtual machine image
===================================

This section explains how to create and use a single-node virtual machine with
Charliecloud and all three builders pre-installed. This lets you use
Charliecloud on Macs and Windows, and/or obtain a pre-configured Charliecloud
environment without installing anything.

You can use this CentOS VM either with `Vagrant <https://www.vagrantup.com>`_
or with `VirtualBox <https://www.virtualbox.org/>`_ alone. Various settings
are specified, but in most cases we have not done any particular tuning, so
use your judgement, and feedback is welcome.

.. warning::

   These instructions provide for an SSH server in the virtual machine guest
   that is accessible to anyone logged into the host. It is your
   responsibility to ensure this is safe and compliant with your
   organization's policies, or modify the procedure accordingly.

Import and use an :code:`ova` appliance file with plain VirtualBox
------------------------------------------------------------------

This procedure imports a :code:`.ova` file into VirtualBox and walks you
through logging in and running a brief Hello World in Charliecloud. You will
act as user :code:`charlie`, who has passwordless :code:`sudo`.

The Charliecloud developers do not distribute a :code:`.ova` file. You will
need to get it from your site, a third party, or build it yourself with
Vagrant using the :ref:`instructions <build-ova>` in the Contributor's guide.

Prerequisite: Installed and working VirtualBox. (You do not need Vagrant to
use the :code:`.ova`, only to create it.)

Configure VirtualBox
~~~~~~~~~~~~~~~~~~~~

1. Set *Preferences* → *Proxy* if needed at your site.

Import the appliance
~~~~~~~~~~~~~~~~~~~~

1. Download :code:`charliecloud_centos7.ova`, or whatever your site
   has called it.
2. *File* → *Import appliance*. Choose :code:`charliecloud_centos7.ova` and
   click *Continue*.
3. Review the settings.

   * CPU should match the number of cores in your system.
   * RAM should be reasonable. Anywhere from 2GiB to half your system RAM will
     probably work.
   * Tick *Reinitialize the MAC address of all network cards*.

4. Click *Import*.
5. Verify that the appliance's port forwarding is acceptable to you and your
   site: *Details* → *Network* → *Adapter 1* → *Advanced* → *Port
   Forwarding*.

Log in and try Charliecloud
~~~~~~~~~~~~~~~~~~~~~~~~~~~

1. Start the VM by clicking the green arrow.

2. Wait for it to boot.

3. Click on the console window, where user :code:`charlie` is logged in. If
   the VM "captures" your mouse pointer, type the key combination listed in
   the lower-right corner of the window to release it. You can avoid capture
   by clicking the title bar instead of window content.

4. Change your password. You must use :code:`sudo` because you have
   passwordless :code:`sudo` but don't know your password.

   ::

     $ sudo passwd charlie

5. SSH (from terminal on the host) into the VM using the password you just
   set. Accessing the VM using SSH rather than the console is generally more
   pleasant, because you have a nice terminal with native copy-and-paste, etc.

   ::

     $ ssh -p 2222 charlie@localhost

6. Build and run a container:

   ::

     $ ch-build -t hello -f /usr/local/src/charliecloud/examples/serial/hello \
                /usr/local/src/charliecloud
     $ ch-builder2tar hello /var/tmp
     57M /var/tmp/hello.tar.gz
     $ ch-tar2dir /var/tmp/hello.tar.gz /var/tmp
     creating new image /var/tmp/hello
     /var/tmp/hello unpacked ok
     $ cat /etc/redhat-release
     CentOS Linux release 7.3.1611 (Core)
     $ ch-run /var/tmp/hello -- /bin/bash
     > cat /etc/debian_version
     8.9
     > exit

Congratulations! You've successfully used Charliecloud. Now all of your
wildest dreams will come true.

Shut down the VM at your leisure.

Possible next steps:

  * Follow the :doc:`tutorial <tutorial>`.
  * Run :ref:`ch-test <ch-test>` (Note that the environment variables are
    already configured for you in this appliance.)
  * Configure :code:`/var/tmp` to be a :code:`tmpfs`, if you have enough RAM,
    for better performance.

Build and use the VM with Vagrant
---------------------------------

This procedure builds and provisions an idiomatic Vagrant virtual machine. You
should also read the Vagrantfile in :code:`packaging/vagrant` before
proceeding. This contains the specific details on build and provisioning,
which are not repeated here.

Prerequisite: You already know how to use Vagrant.

Caveats and gotchas
~~~~~~~~~~~~~~~~~~~

In no particular order:

* While Vagrant supports a wide variety of host and virtual machine providers,
  this procedure is tested only on VirtualBox on a Mac. Current Vagrant
  versions should work, but we don't track specifically which ones. (Anyone
  who wants to help us broaden this support, please get in touch.)

* Switching between proxy and no-proxy environments is not currently
  supported. If you have a mixed environment (e.g. laptops that travel between
  a corporate network and the wild), you may want to provide two separate
  images.

* Provisioning is not idempotent. Running the provisioners again will have
  undefined results.

* The documentation is not built. Use the web documentation instead of man
  pages.

* Only the most recent release of Charliecloud is supported.

Install Vagrant and plugins
~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can install VirtualBox and Vagrant either manually using website downloads
or with Homebrew::

  $ brew cask install virtualbox virtualbox-extension-pack vagrant

Sanity check::

  $ vagrant version
  Installed Version: 2.1.2
  Latest Version: 2.1.2

  You're running an up-to-date version of Vagrant!

Then, install the needed plugins::

  $ vagrant plugin install vagrant-disksize \
                           vagrant-proxyconf \
                           vagrant-reload \
                           vagrant-vbguest

Build and provision
~~~~~~~~~~~~~~~~~~~

To build the VM and install Docker, Charliecloud, etc.::

  $ cd packaging/vagrant
  $ vagrant up

By default, this uses the newest release of Charliecloud. If you want
something different, set the :code:`CH_VERSION` variable, e.g.::

  $ CH_VERSION=v0.10 vagrant up
  $ CH_VERSION=master vagrant up

Then, optionally run the Charliecloud tests::

  $ vagrant provision --provision-with=test

This runs the Charliecloud test suite in standard scope.

Note that the test output does not have a TTY, so you will not have the tidy
checkmarks. The last test printed is the last one that completed, not the one
currently running.

If the tests don't pass, that's a bug. Please report it!

Now you can :code:`vagrant ssh` and do all the usual Vagrant stuff.
