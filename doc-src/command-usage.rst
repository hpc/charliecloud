Charliecloud command reference
******************************

This section is a comprehensive description of the usage and arguments of the
Charliecloud commands. Its content is identical to the commands' man pages.

.. contents::
   :depth: 1
   :local:

.. Note the unusual heading level. This is so the man page .rst files can
   still use double underscores as their top-level headers, which in turn lets
   us do things like include docker_tips.rst. You will also find this in the
   man page .rst files.

ch-build
++++++++

Wrapper for :code:`docker build` with various enhancements.

.. include:: ./ch-build_desc.rst

ch-build2dir
++++++++++++

Build a Charliecloud image from Dockerfile and unpack it into a directory.

.. include:: ./ch-build2dir_desc.rst

ch-docker2tar
+++++++++++++

Flatten a Docker image into a Charliecloud image tarball.

.. include:: ./ch-docker2tar_desc.rst

ch-fromhost
+++++++++++

Inject files from the host into an image directory.

.. include:: ./ch-fromhost_desc.rst

.. _man_ch-run:

ch-pull2dir
+++++++++++

Pull image from a Docker Hub and unpack into directory.

.. include:: ./ch-pull2dir_desc.rst

ch-pull2tar
+++++++++++

Pull image from a Docker Hub and flatten into tarball.

.. include:: ./ch-pull2tar_desc.rst

ch-run
++++++

Run a command in a Charliecloud container.

.. include:: ./ch-run_desc.rst

ch-ssh
++++++

Run a remote command in a Charliecloud container.

.. include:: ./ch-ssh_desc.rst

ch-tar2dir
++++++++++

Unpack an image tarball into a directory.

.. include:: ./ch-tar2dir_desc.rst
