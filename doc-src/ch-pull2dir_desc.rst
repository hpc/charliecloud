Synopsis
========

::

  $ ch-pull2dir IMAGE[:TAG] DIR

Description
===========

Pull a Docker image named :code:`IMAGE[:TAG]` from Docker Hub, flatten it
into a Charliecloud tarball, and extract the tarball into a subdirectory of 
:code:`DIR`.

Sudo privileges are required to run the :code:`docker pull` command.

This runs the following command sequence: `ch-pull2tar` and `ch-tar2dir`.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

.. warning::

   Placing :code:`DIR` on a shared file system can cause significant metadata
   load on the file system servers. This can result in poor performance for
   you and all your colleagues who use the same file system. Please consult
   your site admin for a suitable location.

Examples
========

::

  $ ch-pull2dir alpine /var/tmp
  creating new image /var/tmp/alpine
  /var/tmp/alpine unpacked ok
  $ ls -lh /var/tmp
  total 0
  drwxr-xr-x. 18 charlie 231 Oct  5 20:09 alpine/

Same as above except optional :code: `TAG` argument is assigned:

::

  $ ch-pull2dir alpine:3.6 /var/tmp
  creating new image /var/tmp/alpine:3.6
  /var/tmp/alpine:3.6 unpacked ok
  charlie@localhost:bin $ ls -lh /var/tmp
  total 0
  drwxrwxr-x. 18 charlie 231 Oct 17 08:05 alpine:3.6/
