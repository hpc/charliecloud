Synopsis
========

:code:`ch-tar2dir` TARBALL DIR

Description
===========

Extract the tarball TARBALL into the directory DIR. The tarball TARBALL must be
a Linux filesystem image, as e. g. created by :code:`ch-docker2tar`. Inside the directory
DIR a new subdirectory will be created whose name corresponds to the name of the
tarball with the .tar.gz suffix removed, i. e. if the tarball is e. g. called foo.tar.gz
the contents of the tarball will be put into the directory DIR/foo. If such a directory
exists already and appears to be a Charliecloud container image, it is removed and replaced.
Otherwise, the script aborts with an error.

    :code:`--help`
        Give this help list

    :code:`--version`
        print version and exit

    :code:`--verbose`
        be more verbose

.. WARNING:: Placing DIR on a shared file system can cause significant meta-data load on the
   file system servers. This can result in poor performance for you and all your colleagues
   who use the same file system. Please consult your site admin for a suitable location.
