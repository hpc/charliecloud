Docker tips
===========

Docker is a convenient way to build Charliecloud images. While installing
Docker is beyond the scope of this documentation, here are a few tips.

Understand the security implications of Docker
----------------------------------------------

Because Docker (a) makes installing random crap from the internet really easy
and (b) is easy to deploy insecurely, you should take care. Some of the
implications are below. This list should not be considered comprehensive nor a
substitute for appropriate expertise; adhere to your moral and institutional
responsibilities.

:code:`docker` equals root
~~~~~~~~~~~~~~~~~~~~~~~~~~

Anyone who can run the :code:`docker` command or interact with the Docker
daemon can `trivially escalate to root
<http://web.archive.org/web/20170614013206/http://www.reventlov.com/advisories/using-the-docker-command-to-root-the-host>`_.
This is considered a feature.

For this reason, don't create the :code:`docker` group, as this will allow
passwordless, unlogged escalation for anyone in the group.

Images can contain bad stuff
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Standard hygiene for "installing stuff from the internet" applies. Only work
with images you trust. The official Docker Hub repositories can help.

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

Configuring for a proxy
-----------------------

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

The second problem is that Docker containers need to know about the proxy as
well. This manifests as images failing to build because they can't download
stuff from the internet.

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
test suite (see below) includes a test that fails if some but not all of the
above variables are set.
