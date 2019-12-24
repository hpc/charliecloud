Synopsis
========

::

  $ ch-pull2tar IMAGE[:TAG] OUTDIR

Description
===========

Pull a Docker image named :code:`IMAGE[:TAG]` from Docker Hub and flatten it
into a Charliecloud tarball in directory :code:`OUTDIR`.

This runs the following command sequence: :code:`docker pull`,
:code:`ch-builder2tar` but provides less flexibility than the individual
commands.

Sudo privileges are required for :code:`docker pull`.

Additional arguments:

  :code:`--help`
    print help and exit

  :code:`--version`
    print version and exit

Examples
========

::

  $ ch-pull2tar alpine /var/tmp
  Using default tag: latest
  latest: Pulling from library/alpine
  Digest: sha256:621c2f39f8133acb8e64023a94dbdf0d5ca81896102b9e57c0dc184cadaf5528
  Status: Image is up to date for alpine:latest
  -rw-r--r--. 1 charlie charlie 2.1M Oct  5 19:52 /var/tmp/alpine.tar.gz

Same as above, except optional :code:`TAG` is specified:

::

  $ ch-pull2tar alpine:3.6
  3.6: Pulling from library/alpine
  Digest: sha256:cc24af836d1377e092ecb4e8f0a4324c3b1aa2b5295c2239edcc7bbc86a9cbc6
  Status: Image is up to date for alpine:3.6
  -rw-r--r--. 1 charlie charlie 2.1M Oct  5 19:54 /var/tmp/alpine:3.6.tar.gz
