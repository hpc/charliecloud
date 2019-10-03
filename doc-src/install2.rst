Installation
************

This section describes what you need to install Charliecloud and how to do so.

Note that installing and using Charliecloud requires no privilege, provided
that user namespaces have been enabled in the kernel.

.. contents::
   :depth: 2
   :local:


Build and install from source
=============================

Typical case
------------

The tarballs we provide include the build system (:code:`configure`, etc.) and
pre-built documentation. Thus, build and install is a standard::

  $ ./configure
  $ make
  $ sudo make install

If you don't have sudo, you can:

  * Run Charliecloud directly from the build directory; add :code:`bin` to
    your :code:`$PATH` and you are good to go without :code:`make install`.

  * Install in a prefix you have write access to, e.g. in your home directory
    with :code:`./configure --prefix=~`.

:code:`configure` will provide a detailed report on what will be built and
installed along with what dependencies are present and missing.

:code:`configure` options
-------------------------

.. todo:: I wonder if we should remove this section in favor of
          :code:`./configure --help`?

By default, all features that can be built will be built and installed. Some
features have selectors: :code:`--enable-foo` says to fail the build if
feature :code:`foo`'s dependencies are missing (rather than skipping it),
while :code:`--disable-foo` says not to build and/or install :code:`foo` even
if its dependencies are met.

  ===============  ==========================================
  selector         feature
  ===============  ==========================================
  :code:`html`     HTML documentation
  :code:`man`      Man pages
  :code:`tests`    Test suite
  :code:`ch-grow`  :code:`ch-grow` unprivileged image builder
  ===============  ==========================================

Dependencies (note that :code:`--without-foo` is not supported; use feature
selectors above):

:code:`--with-sphinx-build`
  Path to :code:`sphinx-build` executable.

:code:`--with-run-python`
  Python executable to use in shebang line of scripts. Default:
  :code:`/usr/bin/env python3`.

:code:`--with-build-python`
  Python executable for building Charliecloud. Default: :code:`python3`.

Bootstrapping build system
--------------------------

A Git checkout (or tarball after :code:`make maintainer-clean`) will not have
:code:`configure` or pre-built documentation. To bootstrap, you need GNU
Autotools installed. Run the helper script :code:`configure-bootstrap.sh`.


Install using package manager
=============================


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
versions stated below as we encounter problems, but they are not tight bounds
and may be out of date. Please do let us know any updates you encounter.

Supported architectures
-----------------------

Charliecloud should work on any architecture supported by the Linux kernel,
and we have run Charliecloud containers on x86-64, ARM, and Power. However, it
is currently tested only on x86_64 and ARM.

Most container build software is also fairly portable; e.g., see `Docker's
supported platforms <https://docs.docker.com/install/#supported-platforms>`_.

Overview
--------

This section is a comprehensive summary of dependencies needed for each
feature. Versions are stated in the next section.

Everything needs a POSIX shell and utilities, so that column has been omitted.


.. todo::

   Two alternatives below on how to accomplish this table. Differences:

     #. ASCII art vs. real HTML table (using raw HTML block)
     #. Single table vs. multiple tables.

   This ASCII art is a clunky way to accomplish this table, but Sphinx/ReST
   don't provide a better way. Raw HTML block as above may be an alternative;
   for vertical header cells:
   https://stackoverflow.com/a/47245068
   https://stackoverflow.com/questions/33913304
   https://stackoverflow.com/questions/9434839


   I'm not convinced we need a table, though. It could be each of the
   following tables could be a section with a bullet list.

.. code-block:: none

                                               POSIX environment
                                               |  C11 compiler
                                               |  |  Git
                                               |  |  |  GNU Autotools
                                               |  |  |  |  Sphinx 1.4.9+
                                               |  |  |  |  |  Python 3.4+
   BUILDING CHARLIECLOUD ..................... |  |  |  |  |  |
   build Charliecloud from source              x  x
   bootstrap build from Git clone              x  x  x  x
   re-build documentation [1]                  x           x  x
   build test suite                            x              x

                                               POSIX environment
                                               |  Bash 4.1+
                                               |  |  Docker
                                               |  |  |  mktemp(1)
                                               |  |  |  |  Buildah 1.10.1+
                                               |  |  |  |  |  Python 3.4+
                                               |  |  |  |  |  |  Python module "lark-parser"
                                               |  |  |  |  |  |  |  skopeo
                                               |  |  |  |  |  |  |  |  umoci
   IMAGE BUILDERS ............................ |  |  |  |  |  |  |  |  |
   Docker                                      x  x  x  x
   Buildah                                     x  x        x
   ch-grow                                     x  x           x  x  x  x

                                               POSIX environment
                                               |  Bash 4.1+
                                               |  |  One of the image builders above
                                               |  |  |  Access to image repository
                                               |  |  |  |  SquashFS tools
   MANAGING CONTAINER IMAGES ................  |  |  |  |  |
   build images from Dockerfile with ch-build  x  x  x  x
   push/pull images to/from builder storage    x  x  x  x
   pack image with ch-builder2tar              x  x  x
   pack image with ch-builder2squash           x  x  x     x

                                               POSIX environment
                                               |  user namespaces
                                               |  |  SquashFUSE
   RUNNING CONTAINERS .......................  |  |  |
   ch-run                                      x  x
   unpack image tarballs                       x
   mount/unmount SquashFS images               x     x

                                               POSIX environment
                                               |  Bash 4.1+
                                               |  |  Bats 0.4.0
                                               |  |  |  user namespaces
                                               |  |  |  |  wget
                                               |  |  |  |  |  One of the builders above
                                               |  |  |  |  |  |  Access to image repository
                                               |  |  |  |  |  |  |  Sphinx 1.4.9+
                                               |  |  |  |  |  |  |  |  Python 3.4+
                                               |  |  |  |  |  |  |  |  |  SquashFS tools
                                               |  |  |  |  |  |  |  |  |  |  SquashFUSE
                                               |  |  |  |  |  |  |  |  |  |  |  generic sudo
   TEST SUITE ...............................  |  |  |  |  |  |  |  |  |  |  |  |
   run basic tests                             x  x  x  x  x
   run recommended tests with tarballs         x  x  x  x  x  x  x
   run recommented tests using SquashFS        x  x  x  x  x  x  x        x  x
   run complete test suite                     x  x  x  x  x  x  x  x  x  x  x  x

   [1] Pre-built documentation is provided in release tarballs.

.. todo::

   Problems with this table:

     #. Column headers not centered horizontally.

     #. Background colors not used helpfully (e.g. can we make the header rows
        gray and the rest white?).

     #. First column not frozen on scrolling.

   Assume these are fixed when evaluating.

.. raw:: html

  <style type="text/css">
    table.docutils {
      /* Work around alternating row colors. This only affects the even
         (white) rows. I couldn't find a way to make the odd rows white. */
      background-color: #f3f6f6;
    }
    table.docutils tr th {
      border: 1px solid #e1e4e5;  /* add missing <th> borders */
      text-align: left;
    }
    /* table.docutils tr td.lhead {
      position: absolute;
    } */
    table.docutils tr.rotate td {
      text-align: center;
      vertical-align: bottom;
    }
    table.docutils tr.rotate td span {
      /* https://stackoverflow.com/a/47245068/396038 */
      -ms-writing-mode: tb-rl;
      -webkit-writing-mode: vertical-rl;
      writing-mode: vertical-rl;
      transform: rotate(180deg);
      white-space: nowrap;
    }

  </style>
  <table class="docutils align-center">
  <tbody>
    <tr class="rotate">
      <td></td>

      <td><span>C11 compiler</span></td>
      <td><span>Git</span></td>
      <td><span>GNU Autotools</span></td>
      <td><span>Sphinx</span></td>
      <td><span>Python</span></td>

      <td><span>Bash</span></td>
      <td><span>Docker</span></td>
      <td><span>Buildah</span></td>
      <td><span>Python package “lark-parser”</span></td>
      <td><span>skopeo</span></td>
      <td><span>umoci</span></td>

      <td><span>One of the three image builders</span></td>
      <td><span>Access to image repository</span></td>
      <td><span>SquashFS tools</span></td>
      <td><span>user namespaces</span></td>
      <td><span>SquashFUSE</span></td>

      <td><span>Bats</span></td>
      <td><span>wget</span></td>
      <td><span>generic sudo</span></td>
    </tr>

    <tr>
      <th colspan=20>Building Charliecloud</th>
    </tr>
    <tr>
      <td class="lhead">build Charliecloud from source</td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">bootstrap build from Git clone</td>

      <td></td>
      <td>x</td>
      <td>x</td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">re-build documentation</td>

      <td></td>
      <td></td>
      <td></td>
      <td>x</td>
      <td>x</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">build test suite</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>x</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>

    <tr>
      <th colspan=20>Image builders</th>
    </tr>
    <tr>
      <td class="lhead">Docker</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">Buildah</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td>x</td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">ch-grow</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>x</td>

      <td>x</td>
      <td></td>
      <td></td>
      <td>x</td>
      <td>x</td>
      <td>x</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>

    <tr>
      <th colspan=20>Preparing container images</th>
    </tr>
    <tr>
      <td class="lhead">build images from Dockerfile with <tt>ch-build</tt></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">push/pull images to/from builder storage</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">pack image with <tt>ch-builder2tar</tt></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">pack image with <tt>ch-builder2squash</tt></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td>x</td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>

    <tr>
      <th colspan=20>Running containers</th>
    </tr>
    <tr>
      <td class="lhead"><tt>ch-run</tt></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td>x</td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">unpack image tarballs</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">mount/unmount SquashFS images</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>x</td>

      <td></td>
      <td></td>
      <td></td>
    </tr>

    <tr>
      <th colspan=20>Running test suite</th>
    </tr>
    <tr>
      <td class="lhead">basic tests</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td></td>
      <td></td>
      <td></td>
      <td>x</td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">recommended tests using tarballs</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
      <td>x</td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">recommended tests using SquashFS</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td>x</td>
      <td>x</td>
      <td>x</td>

      <td>x</td>
      <td>x</td>
      <td></td>
    </tr>
    <tr>
      <td class="lhead">complete test suite</td>

      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>

      <td>x</td>
      <td>x</td>
      <td>x</td>
      <td>x</td>
      <td>x</td>

      <td>x</td>
      <td>x</td>
      <td>x</td>
    </tr>

  </tbody>
  </table>

Overview
--------

This section is a comprehensive list of dependencies needed for each feature.
Versions are stated in the next section.

Everything needs a POSIX shell and utilities.

Building Charliecloud
~~~~~~~~~~~~~~~~~~~~~

.. |br| raw:: html

   <br/>

.. list-table::
   :header-rows: 1

   * - in order to
     - you need

   * - build Charliecloud from source
     - C11 compiler (but not Intel CC)

   * - bootstrap build from Git
     - Git
       |br| GNU Autotools

   * - re-build documentation [1]
     - Python
       |br| Sphinx

   * - build test stuie
     - Python

Build Charliecloud from source:

  * C11 compiler (but not Intel CC)

Bootstrap build from Git:

  * Git
  * GNU Autotools

Re-build documentation:

  * Python
  * Sphinx

Build test suite:

  * Python

Note: Built documentation is included in the tarballs.

Details
-------

There are more details for some of the dependencies; these are listed below.

C11 compiler
~~~~~~~~~~~~

We test with GCC. Core team members use whatever version comes with their
distribution.

In principle, any C11 compiler should work. Please let us know any success or
failure reports.

Intel :code:`icc` is not supported because it links extra shared libraries
that our test suite can't deal with. See `PR #481
<https://github.com/hpc/charliecloud/pull/481>`_.

GNU Autotools
~~~~~~~~~~~~~

.. todo::

   Do we want to say anything here? What specifically do people need to
   install?

Sphinx
~~~~~~

We use Sphinx to build the documentation. Minimum version is 1.4.9, but we use
pretty close to current for building what's on the web.

Python
~~~~~~

Python minimum version is 3.4. We use it for scripts that would be really hard
to do in Bash, when we think Python is likely to be available.

Bash
~~~~

When Bash is needed, it's because:

  * Shell scripting is a lot easier in Bash than POSIX shell, so we use it for
    scripts applicable in contexts where it's very likely Bash is already
    available.

  * It is required by our testing framework, Bats.

Minimum version is Bash 4.1, because it has important bug fixes.

Docker
~~~~~~

We do not rigorously test which Docker versions work. We know that 1.7.1 does
not.

Our wrapper scripts for Docker expect to run the :code:`docker` command under
:code:`sudo`.

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
  passwordless, unlogged escalation for anyone in the group.

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

The fix is to set the proxy variables in your environment, e.g.::

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

Buildah
~~~~~~~

Minimum Buildah is v1.10.1.

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

Python package "lark-parser"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

PyPI has two incompatible packages that provide the module :code:`lark`,
"`lark-parser <https://pypi.org/project/lark-parser/>`_" and "lark". You want
"lark-parser".

skopeo
~~~~~~

.. todo:: Do we have anything to say about installing `skopeo
          <https://github.com/containers/skopeo>`_?

umoci
~~~~~

.. todo:: Do we have anything to say about intsalling `umoci
          <https://github.com/openSUSE/umoci>`_?

One of the image builders
~~~~~~~~~~~~~~~~~~~~~~~~~

.. todo:: Do we have anything to say here???

Access to image repository
~~~~~~~~~~~~~~~~~~~~~~~~~~

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

SquashFS
~~~~~~~~

The SquashFS workflow requires `SquashFS Tools
<https://github.com/plougher/squashfs-tools>`_ and/or `SquashFUSE
<https://github.com/vasi/squashfuse>`_. Note that distribution packages of
SquashFUSE often provide only the "high level" executables; the "low level"
executables have better performance. These can be installed from source on any
distribution.

User namespaces
~~~~~~~~~~~~~~~

In order to enable `user namespaces <https://lwn.net/Articles/531114/>`_, you
need a vaguely recent Linux kernel with the feature compiled in and active.

Some distributions need configuration changes to enable user namespaces. For
example:

* Debian Stretch `needs sysctl <https://superuser.com/a/1122977>`_
  :code:`kernel.unprivileged_userns_clone=1`.

* RHEL/CentOS 7.4 and 7.5 need both a `kernel command line option and a sysctl <https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_atomic_host/7/html-single/getting_started_with_containers/#user_namespaces_options>`_.
  *Important note:* Docker does not work with user namespaces, so skip step 4
  of the Red Hat instructions, i.e., don't add :code:`--userns-remap` to the
  Docker configuration (see `issue #97
  <https://github.com/hpc/charliecloud/issues/97>`_).

Bats
~~~~

Bats ("Bash Automated Testing System") is a test framework for tests written
as Bash shell scripts.

`Upstream Bats <https://github.com/sstephenson/bats>`_ is unmaintained, but
widely available. Both version 0.4.0, which tends to be in distributions, and
upstream master branch (commit 0360811) should work.

There is a maintained fork called `Bats-core
<https://github.com/bats-core/bats-core>`_, but we have not yet tried it.
Patches welcome!

Wget
~~~~

Wget is used to demonstrate building an image without a builder (the main test
image used to exercise Charliecloud itself).

Generic sudo
~~~~~~~~~~~~

Privilege escalation via sudo is used in the test suite to:

  * Prepare fixture directories for testing filesystem permissions enforcement.
  * Test :code:`ch-run`'s behavior under different ownership scenarios.

(Note that Charliecloud also uses :code:`sudo docker`; see above.)
