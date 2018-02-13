Usage of Charliecloud commands
******************************

This sections describes how to use the Charliecloud commands.

.. WARNING: The one-line summaries below are duplicated in list man_pages in
   conf.py. Any updates need to be made there also.

.. Note the unusual heading level. This is so the man page .rst files can
   still use double underscores as their top-level headers, which in turn lets
   us do things like include docker_tips.rst. You will also find this in the
   man page .rst files.

ch-build
++++++++

Wrapper for :code:`docker build` that works around some of its annoying
behaviors.

.. include:: ./ch-build_desc.rst

ch-build2dir
++++++++++++

Build a Charliecloud image from Dockerfile and unpack it.

.. include:: ./ch-build2dir_desc.rst

ch-docker2tar
+++++++++++++

Flatten a Docker image into a Charliecloud image tarball.

.. include:: ./ch-docker2tar_desc.rst

ch-docker-run
+++++++++++++

Run a command in a Docker container.

.. include:: ./ch-docker-run_desc.rst

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
