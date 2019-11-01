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

ch-build
++++++++

Build an image and place it in the builder's back-end storage.

.. include:: ./ch-build_desc.rst

ch-build2dir
++++++++++++

Build a Charliecloud image from Dockerfile and unpack it into a directory.

.. include:: ./ch-build2dir_desc.rst

ch-builder2tar
++++++++++++++

Flatten a builder image into a Charliecloud image tarball.

.. include:: ./ch-builder2tar_desc.rst

ch-checkns
++++++++++

Check :code:`ch-run` prerequisites, e.g., namespaces and :code:`pivot_root(2)`.

.. include:: ./ch-checkns_desc.rst

ch-dir2squash
+++++++++++++

Create a SquashFS file from an image directory.

.. include:: ./ch-dir2squash_desc.rst

ch-builder2squash
+++++++++++++++++

Flatten a builder image into a Charliecloud SquashFS file.

.. include:: ./ch-builder2squash_desc.rst

ch-fromhost
+++++++++++

Inject files from the host into an image directory.

.. include:: ./ch-fromhost_desc.rst

ch-grow
+++++++

Build an image from a Dockerfile; completely unprivileged.

.. include:: ./ch-grow_desc.rst

ch-mount
++++++++

Mount a SquashFS image file using FUSE.

.. include:: ./ch-mount_desc.rst

ch-pull2dir
+++++++++++

Pull image from a Docker Hub and unpack into directory.

.. include:: ./ch-pull2dir_desc.rst

ch-pull2tar
+++++++++++

Pull image from a Docker Hub and flatten into tarball.

.. include:: ./ch-pull2tar_desc.rst

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

ch-tar2dir
++++++++++

Unpack an image tarball into a directory.

.. include:: ./ch-tar2dir_desc.rst

ch-tar2squash
+++++++++++++

Create a SquashFS file from a tarball image.

.. include:: ./ch-tar2squash_desc.rst

.. _ch-test:

ch-test
+++++++

Run some or all of the Charliecloud test suite.

.. include:: ./ch-test_desc.rst

ch-umount
+++++++++

Unmount a FUSE mounted squash filesystem and remove the mount point.

.. include:: ./ch-umount_desc.rst
