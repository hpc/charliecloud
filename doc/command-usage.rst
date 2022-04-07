Charliecloud command reference
******************************

This section is a comprehensive description of the usage and arguments of the
Charliecloud commands. Its content is identical to the commands' man pages.

.. contents::
   :depth: 1
   :local:

.. Note the unusual heading level. This is so the man page .rst files can
   still use double underscores as their top-level headers. You will also find
   this in the man page .rst files.


ch-checkns
++++++++++

Check :code:`ch-run` prerequisites, e.g., namespaces and :code:`pivot_root(2)`.

.. include:: ./ch-checkns_desc.rst

ch-convert
++++++++++

Convert an image from one format to another.

.. include:: ./ch-convert_desc.rst

ch-fromhost
+++++++++++

Inject files from the host into an image directory, with various magic.

.. include:: ./ch-fromhost_desc.rst

ch-image
++++++++

Build and manage images; completely unprivileged.

.. include:: ./ch-image_desc.rst

.. _man_ch-run:

ch-run
++++++

Run a command in a Charliecloud container.

.. include:: ./ch-run_desc.rst

ch-run-oci
++++++++++

OCI wrapper for :code:`ch-run`.

.. include:: ./ch-run-oci_desc.rst

ch-ssh
++++++

Run a remote command in a Charliecloud container.

.. include:: ./ch-ssh_desc.rst

ch-test
+++++++

Run some or all of the Charliecloud test suite.

.. include:: ./ch-test_desc.rst
