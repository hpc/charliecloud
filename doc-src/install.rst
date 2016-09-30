Installation
************

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

* Recent Linux kernel with :code:`CONFIG_USER_NS=y`
* C compiler and standard library
* POSIX shell and utilities

The kernel version is vague because it's not a simple number. The upstream
kernel documentation says 3.10+ is sufficient. However, RHEL7 derivatives have
a patch to disable user namespaces in concert with mount namespaces. Tested by
us and working are 4.2 (Ubuntu) and 4.4 (Ubuntu as well as upstream
:code:`kernel.org`).

Build time
----------

Systems used for building images need the run-time prerequisites, plus:

* `Docker <https://www.docker.com/>`_, recent version. We do not make compatibility guarantees with any specific version, but let us know if you run into issues.
* bash
* root access using :code:`sudo`


Verifying the system calls
==========================

The :code:`examples` directory includes a C program that exercises the key
system calls Charliecloud depends on. If this works, then Charliecloud
probably will too::

  $ cd examples/syscalls
  $ make
  $ ./pivot_root
  ok

If :code:`pivot_root` instead reports an error, check the reported line number
in :code:`pivot_root.c` to see what failed.


Installing Docker
=================

While installing Docker is beyond the scope of this documentation, here are a
few tips.

Understand the security implications of Docker
----------------------------------------------

Because Docker (a) makes installing random crap from the internet really easy
and (b) has an "interesting" security culture, you should take care. Some of
the implications are below. This list should not be considered comprehensive
nor a substitute for appropriate expertise; adhere to your moral and
institutional responsibilities.

(All this stuff is a key motivation for Charliecloud.)

Don't pipe web pages to your shell
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This is how Docker recommends you install the software. Don't do this::

  $ curl -fsSL https://get.docker.com/ | sh

This approach --- piping a web page directly into a shell --- is easy and
fashionable but stupid.

The problem is that you've invited the web page to execute arbitrary code as
you (or worse, root). Auditing the page in a browser only helps somewhat, as
the server could use your :code:`User-Agent` header to decide whether to show
you safe or malicious code.

Download the script to a file and audit it carefully before running.

:code:`docker` equals root
~~~~~~~~~~~~~~~~~~~~~~~~~~

Anyone who can run the :code:`docker` command or interact with the Docker
daemon can `trivially escalate to root
<http://reventlov.com/advisories/using-the-docker-command-to-root-the-host>`_.
This is considered a feature.

For this reason, don't create the :code:`docker` group when the installer
offers it, as this will allow passwordless, unlogged escalation for anyone in
the group.

Images can contain bad stuff
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Standard hygiene for "installing stuff from the internet" applies. Only work
with images you trust. The official DockerHub repositories can help.

Containers run as root
~~~~~~~~~~~~~~~~~~~~~~

By default, Docker runs container processes as root. In addition to being poor
hygiene, this can be an escalation path, e.g. if you bind-mount host
directories.

Docker alters your network configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To see what it did::

  $ ifconfig    # note docker0 interface
  $ brctl show  # note docker0 bridge
  $ route -n

Docker installs services
~~~~~~~~~~~~~~~~~~~~~~~~

If you don't want the service starting automatically at boot, e.g.::

  $ systemctl is-enabled docker
  enabled
  $ systemctl disable docker
  $ systemctl is-enabled docker
  disabled

Configuring Docker for a proxy
------------------------------

By default, Docker does not work if you have a proxy. The symptom is this::

  $ sudo docker run hello-world
  Unable to find image 'hello-world:latest' locally
  Pulling repository hello-world
  Get https://index.docker.io/v1/repositories/library/hello-world/images: dial tcp 54.152.161.54:443: connection refused

The solution is to configure an override file :code:`http-proxy.conf` as
`documented <https://docs.docker.com/articles/systemd/>`_. If you don't have a
systemd system, then :code:`/etc/default/docker` might be the place to go.


Installing Charliecloud
=======================

All you need in order to use Charliecloud is the contents of :code:`bin`::

  $ cd bin
  $ make
  cc -std=c11 -Wall -Werror -Wfatal-errors -o ch-run ch-run.c

You could put this directory in your :code:`$PATH` or link/copy the contents
to somewhere else.

That said, in order to understand Charliecloud, including completing the
tutorial in the next section, you will want access to the rest of the source
code as well.

If you wish to build the documentation, see :code:`doc-src/README`.
