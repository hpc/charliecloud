Tutorial
********

This tutorial will teach you how to create and run Charliecloud images, using
both examples included with the source code as well as new ones you create
from scratch.

This tutorial assumes that Charliecloud is correctly installed as described in
the previous section, that the :code:`bin` directory is on your
:code:`$PATH`, and that you have access to the examples in the source code.

.. contents::
   :depth: 2
   :local:


Getting help
============

All the Charliecloud executables have decent help (if not, please report a
bug). For example::

  $ ch-run --help

This help text is also collected later in this documentation; see
:doc:`script-help`.


Your first user-defined software stack
======================================

In this section, we will create and run a simple "hello, world" image. This
uses the :code:`hello` example in the Charliecloud source code. Start with::

  $ cd examples/hello

Defining your UDSS
------------------

You must first write a Dockerfile that describes the image you would like;
consult the `Dockerfile documentation
<https://docs.docker.com/engine/reference/builder/>`_ for details on how to do
this. Note that run-time functionality such as :code:`ENTRYPOINT` is not
supported.

We will use the following very simple Dockerfile::

  $ cat Dockerfile
  FROM debian:jessie
  RUN    apt-get update \
      && apt-get install -y openssh-client \
      && rm -rf /var/lib/apt/lists/*

This creates a minimal Debian Jessie image with :code:`ssh` installed. We will
encounter more complex Dockerfiles later in this tutorial.

.. note::

   Docker does not update the base image unless asked to. Specific images can
   be updated manually; in this case::

     $ sudo docker pull debian:jessie

   There are various resources and scripts online to help automate this
   process.

Build Docker image
------------------

Charliecloud provides an optional convenience wrapper around :code:`docker
build` that works around some of its more irritating characteristics. In
particular, it passes through any HTTP proxy variables, and by default it uses
the Dockerfile in the current directory, rather than at the root of the Docker
context directory. (We will address the context directory later.)

The two arguments here are a tag for the Docker image and the context
directory, which in this case is the Charliecloud source code.

::

  $ docker-build -t $USER/hello ../..
  Sending build context to Docker daemon 8.105 MB
  Step 1 : FROM debian:jessie
   ---> ddf73f48a05d
  Step 2 : RUN apt-get update && apt-get install -y openssh-client
   ---> Running in beadfda45e4c
  [...]
   ---> 526e2ca75656
  Removing intermediate container beadfda45e4c
  Successfully built 526e2ca75656

:code:`docker-build` and many other Charliecloud commands wrap various
privileged `docker` commands. Thus, you will be prompted for a password to
escalate as needed. Note however that most configurations of :code:`sudo`
don't require a password on every invocation, so just because you aren't
prompted doesn't mean privileged commands aren't running.

Share image and other standard Docker stuff
-------------------------------------------

If needed, the Docker image can be manipulated with standard Docker commands.
In particular, image sharing using a public or private Docker Hub repository
can be very useful.

::

  $ sudo docker images
  REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
  debian              jessie              1742affe03b5        10 days ago         125.1 MB
  reidpr/hello        latest              1742affe03b5        10 days ago         139.7 MB
  $ sudo docker push  # FIXME

Running the image with Docker is not generally useful, because Docker's
run-time environment is significantly different than Charliecloud's, but it
can have value when debugging Charliecloud.

::

  $ sudo docker run -it $USER/hello /bin/bash
  root@6e5c514e0296:/# ls /
  bin   dev  home  lib64	mnt  proc  run	 srv  tmp  var
  boot  etc  lib	 media	opt  root  sbin  sys  usr
  root@6e5c514e0296:/# exit
  exit

Flatten image
-------------

Next, we flatten the Docker image into a tarball, which is then a plain file
amenable to standard file manipulation commands. This tarball is placed in an
arbitrary directory, here :code:`/data`.

::

   $ ch-docker2tar $USER/hello /data
   57M /data/reidpr.hello.tar.gz

Distribute tarball
------------------

Thus far, the workflow has taken place on the build system. The next step is
to move the tarball to the run system. This can use any appropriate method for
moving files: :code:`scp`, :code:`rsync`, something integrated with the
scheduler, etc.

If the build and run systems are the same, then no move is needed. This is a
typical use case for the testing phase.

Unpack tarball
--------------

Charliecloud runs out of a normal directory rather than a filesystem image. In
order to create this directory, we unpack the image tarball. This will replace
the image directory if it already exists.

::

   $ ch-tar2dir /data/$USER.hello.tar.gz /data/$USER.hello
   /data/reidpr.hello unpacked ok

One potential gotcha is the tarball including special files such as devices.
Because :code:`tar` is running unprivileged, these will not be unpacked, but
they can cause the extraction to fail. The fix is to delete them in the
Dockerfile.

.. note::

   You can run perfectly well out of :code:`/tmp`, but because it is
   bind-mounted automatically, the image root will then appear in multiple
   locations in the container's filesystem tree. This can cause confusion for
   both users and programs.

Activate image
--------------

We are now ready to run programs inside a Charliecloud container. This is done
with the :code:`ch-run` command::

  $ ch-run /data/$USER.hello -- echo hello
  hello

Symbolic links in :code:`/proc` tell us the current namespaces, which are
identified by long ID numbers::

  $ ls -l /proc/self/ns
  total 0
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 11:24 ipc -> ipc:[4026531839]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 11:24 mnt -> mnt:[4026531840]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 11:24 net -> net:[4026531969]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 11:24 pid -> pid:[4026531836]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 11:24 user -> user:[4026531837]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 11:24 uts -> uts:[4026531838]
  $ ch-run /data/$USER.hello -- ls -l /proc/self/ns
  total 0
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 17:34 ipc -> ipc:[4026531839]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 17:34 mnt -> mnt:[4026532257]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 17:34 net -> net:[4026531969]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 17:34 pid -> pid:[4026531836]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 17:34 user -> user:[4026532256]
  lrwxrwxrwx 1 reidpr reidpr 0 Sep 28 17:34 uts -> uts:[4026531838]

Notice that the container has different mount (:code:`mnt`) and user
(:code:`user`) namespaces, but the rest of the namespaces are shared with the
host. This highlights Charliecloud's focus on functionality (make your UDSS
run), rather than isolation (protect the host from your UDSS).

Each invocation of :code:`ch-run` creates a new container, so if you have
multiple simultaneous invocations, they will not share containers. However,
container overhead is minimal, and containers communicate without hassle, so
this is generally of peripheral interest.

.. note::

   The :code:`--` in the :code:`ch-run` command line is a standard argument
   that separates options from non-option arguments. Without it,
   :code:`ch-run` would try (and fail) to interpret :code:`ls`’s :code:`-l`
   argument.

These IDs are available both in the symlink target as well as its inode
number::

  $ stat -L --format='%i' /proc/self/ns/user
  4026531837
  $ ch-run /data/$USER.hello -- stat -L --format='%i' /proc/self/ns/user
  4026532256

You can also run interactive commands, such as a shell::

  $ ch-run /data/$USER.hello -- /bin/bash
  $ stat -L --format='%i' /proc/self/ns/user
  4026532256
  $ exit

Be aware that wildcards in the :code:`ch-run` command are interpreted by the
host, not the container, unless protected. One workaround is to use a
sub-shell. For example::

  $ ls /usr/bin/oldfind
  ls: cannot access '/usr/bin/oldfind': No such file or directory
  $ ch-run /data/$USER.hello -- ls /usr/bin/oldfind
  /usr/bin/oldfind
  $ ls /usr/bin/oldf*
  ls: cannot access '/usr/bin/oldf*': No such file or directory
  $ ch-run /data/$USER.hello -- ls /usr/bin/oldf*
  ls: cannot access /usr/bin/oldf*: No such file or directory
  $ ch-run /data/$USER.hello -- sh -c 'ls /usr/bin/oldf*'
  /usr/bin/oldfind

You have now successfully run commands within a single-node Charliecloud
container. Next, we explore how Charliecloud accesses host resources.


Interacting with the host
=========================

Charliecloud is not an isolation layer, so containers have full access to host
resources, with a few quirks. This section demonstrates how this works.

Filesystems
-----------

Charliecloud makes host directories available inside the container using bind
mounts, which is somewhat like a hard link in that it causes a file or
directory to appear in multiple places in the filesystem tree, but it is a
property of the running kernel rather than the filesystem.

Several host directories are always bind-mounted into the container. These
include system directories such as :code:`/dev`, :code:`/proc`, and
:code:`/sys`; :code:`/tmp`; and the invoking user's home directory (for
dotfiles).

.. and the Charliecloud source at :code:`/mnt/ch`.

Charliecloud uses recursive bind mounts, so for example if the host has a
variety of sub-filesystems under :code:`/sys`, as Ubuntu does, these will be
available in the container as well.

In addition to the default bind mounts, arbitrary user-specified directories
can be added using the :code:`-d` switch. These appear at :code:`/mnt/0`,
:code:`/mnt/0`, etc. For example::

  $ mkdir /data/foo0
  $ echo hello > /data/foo0/bar
  $ mkdir /data/foo1
  $ echo world > /data/foo1/bar
  $ ch-run -d /data/foo0 -d /data/foo1 /data/$USER.hello bash
  > ls /mnt
  0  1
  > cat /mnt/0/bar
  hello
  > cat /mnt/1/bar
  world

Network
-------

Charliecloud containers share the host's network namespace, so most network
things should be the same.

However, SSH is not aware of Charliecloud containers. If you SSH to a node
where Charliecloud is installed, you will get a shell on the host, not in a
container, even if :code:`ssh` was initiated from a container::

  $ stat -L --format='%i' /proc/self/ns/user
  4026531837
  $ ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026531837
  $ ch-run /data/$USER.hello -- /bin/bash
  > stat -L --format='%i' /proc/self/ns/user
  4026532256
  > ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026531837

There are several ways to SSH to a remote note and run commands inside a
container. The simplest is to manually invoke :code:`ch-run` in the
:code:`ssh` command::

  $ ssh localhost ch-run /data/$USER.hello -- stat -L --format='%i' /proc/self/ns/user
  4026532256

.. note::

   Recall that each :code:`ch-run` invocation creates a new container. That
   is, the :code:`ssh` command above has not entered an existing user
   namespace :code:`’2256`; rather, it has re-used the namespace ID
   :code:`’2256`.

Another is to use the :code:`ch-ssh` wrapper program, which adds
:code:`ch-run` to the :code:`ssh` command implicitly. It takes the
:code:`ch-run` arguments from the environment variable :code:`CH_RUN_ARGS`,
making it mostly a drop-in replacement for :code:`ssh`. For example::

  $ export CH_RUN_ARGS="/data/$USER.hello --"
  $ ch-ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026532256
  $ ch-ssh -t localhost /bin/bash
  > stat -L --format='%i' /proc/self/ns/user
  4026532256

.. warning::

   1. :code:`CH_RUN_ARGS` is interpreted very simply; the sole delimiter is
      spaces. It is not shell syntax. In particular, quotes and backslashes
      are not interpreted.

   2. Argument :code:`-t` is required for SSH to allocate a pseudo-TTY and
      thus convince your shell to be interactive. In the case of Bash,
      otherwise you'll get a shell that accepts commands but doesn't print
      prompts, amother other issues. (`Issue #2
      <https://github.com/hpc/charliecloud/issues/2>`_.)

A third may be to edit one's shell initialization scripts to check the command
line and :code:`exec(1)` :code:`ch-run` if appropriate. This is brittle but
avoids wrapping :code:`ssh` or altering its command line.

User and group IDs
------------------

Unlike Docker and some other container systems, Charliecloud tries to make the
container's users and groups look the same as the hosts. (This is accomplished
by bind-mounting :code:`/etc/passwd` and :code:`/etc/group` into the
container.) For example::

  $ id -u
  1001
  $ whoami
  reidpr
  $ ch-run /data/$USER.hello bash
  > id -u
  1001
  > whoami
  reidpr

More specifically, the user namespace, when created without privileges as
Charliecloud does, lets you map any container UID to your host UID.
:code:`ch-run` implements this with the :code:`--uid` switch. So, for example,
you can tell Charliecloud you want to be root, and it will tell you that
you're root::

  $ ch-run --uid 0 /data/$USER.hello bash
  > id -u
  0
  > whoami
  root

But, this doesn't get you anything useful, because the container UID is mapped
back to your UID on the host before permission checks are applied::

  > dd if=/dev/mem of=/tmp/pwned
  dd: failed to open '/dev/mem': Permission denied

This mapping also affects how users are displayed. For example, if a file is
owned by you, your host UID will be mapped to your container UID, which is
then looked up in :code:`/etc/passwd` to determine the display name. In
typical usage without :code:`--uid`, this mapping is a no-op, so everything
looks normal::

  $ ls -nd ~
  drwxr-xr-x 87 1001 1001 4096 Sep 28 12:12 /home/reidpr
  $ ls -ld ~
  drwxr-xr-x 87 reidpr reidpr 4096 Sep 28 12:12 /home/reidpr
  $ ch-run /data/$USER.hello bash
  > ls -nd ~
  drwxr-xr-x 87 1001 1001 4096 Sep 28 18:12 /home/reidpr
  > ls -ld ~
  drwxr-xr-x 87 reidpr reidpr 4096 Sep 28 18:12 /home/reidpr

But if :code:`--uid` is provided, things can seem odd. For example::

  $ ch-run --uid 0 /data/$USER.hello bash
  > ls -nd /home/reidpr
  drwxr-xr-x 87 0 1001 4096 Sep 28 18:12 /home/reidpr
  > ls -ld /home/reidpr
  drwxr-xr-x 87 root reidpr 4096 Sep 28 18:12 /home/reidpr

This UID mapping can contain only one pair: an arbitrary container UID to your
effective UID on the host. Thus, all other users are unmapped, and they show
up as :code:`nobody`::

  $ ls -n /tmp/foo
  -rw-rw---- 1 1002 1002 0 Sep 28 15:40 /tmp/foo
  $ ls -l /tmp/foo
  -rw-rw---- 1 sig sig 0 Sep 28 15:40 /tmp/foo
  $ ch-run /data/$USER.hello bash
  > ls -n /tmp/foo
  -rw-rw---- 1 65534 65534 843 Sep 28 21:40 /tmp/foo
  > ls -l /tmp/foo
  -rw-rw---- 1 nobody nogroup 843 Sep 28 21:40 /tmp/foo

User namespaces have a similar mapping for GIDs, with the same limitation ---
exactly one arbitrary container GID maps to your effective *primary* GID. This
can lead to some strange-looking results, because only one of your GIDs can be
mapped in any given container. All the rest become :code:`nogroup`::

  $ id
  uid=1001(reidpr) gid=1001(reidpr) groups=1001(reidpr),1003(nerds),1004(losers)
  $ ch-run /data/$USER.hello -- id
  uid=1001(reidpr) gid=1001(reidpr) groups=1001(reidpr),65534(nogroup)
  $ ch-run --gid 1003 /data/$USER.hello -- id
  uid=1001(reidpr) gid=1003(nerds) groups=1003(nerds),65534(nogroup)

However, this doesn't affect access. The container process retains the same
GIDs from the host perspective, and as always, the host IDs are what control
access::

  $ ls -l /tmp/primary /tmp/supplemental
  -rw-rw---- 1 sig reidpr 0 Sep 28 15:47 /tmp/primary
  -rw-rw---- 1 sig nerds  0 Sep 28 15:48 /tmp/supplemental
  $ ch-run /data/$USER.hello bash
  > cat /tmp/primary > /dev/null
  > cat /tmp/supplemental > /dev/null

One area where functionality *is* reduced is that :code:`chgrp(1)` becomes
useless. Using an unmapped group or :code:`nogroup` fails, and using a mapped
group is a no-op because it's mapped back to the host GID::

  $ ls -l /tmp/bar
  rw-rw---- 1 reidpr reidpr 0 Sep 28 16:12 /tmp/bar
  $ ch-run /data/$USER.hello -- chgrp nerds /tmp/bar
  chgrp: changing group of '/tmp/bar': Invalid argument
  $ ch-run /data/$USER.hello -- chgrp nogroup /tmp/bar
  chgrp: changing group of '/tmp/bar': Invalid argument
  $ ch-run --gid 1003 /data/$USER.hello -- chgrp nerds /tmp/bar
  $ ls -l /tmp/bar
  -rw-rw---- 1 reidpr reidpr 0 Sep 28 16:12 /tmp/bar

Workarounds include :code:`chgrp(1)` on the host or fastidious use of setgid
directories::

  $ mkdir /tmp/baz
  $ chgrp nerds /tmp/baz
  $ chmod 2770 /tmp/baz
  $ ls -ld /tmp/baz
  drwxrws--- 2 reidpr nerds 40 Sep 28 16:19 /tmp/baz
  $ ch-run /data/$USER.hello -- touch /tmp/baz/foo
  $ ls -l /tmp/baz/foo
  -rw-rw---- 1 reidpr nerds 0 Sep 28 16:21 /tmp/baz/foo

This concludes our discussion of how a Charliecloud container interacts with
its host. principal Charliecloud quirks. We next move on to installing
software.


Installing your own software
============================

There are

Most of Docker's `Best practices for writing Dockerfiles
<https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices>`_
apply to Charliecloud images as well.

only install software if you have to ... maybe there's already a trustable Docker image you can use as a base

installing with OS package managers -- sl
compiling third-party software -- download and install sl from source
installing your code into the image -- download on host, COPY to image
running code on the host -- download on host

This script is available at :code:`/mnt/ch/bin/ch-ssh` inside containers. It
requires :code:`ssh` to be on :code:`$PATH` inside the container::

  $ ch-run /data/$USER.hello /bin/bash
  > export CH_RUN_ARGS="/data/$USER.hello --"
  > /mnt/ch/bin/ch-ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026532256

Install into image or not?
--------------------------

Your first single-node, multi-process job
===========================================

a little artificial as there's no real point in multiple identical containers
on a single node

Your first multi-node job
=========================

two models
  host coordinates, each task in own container - mpirun on host
    needs close version matching with host, e.g. OpenMPI needs to be compiled the same
  container coordinates - mpirun in container
    ch-ssh to arrive at other host inside container

The image directory will be mounted read-only, so it can be shared by multiple
Charliecloud instances in the same or different jobs.

Any filesystem can be used, but be aware of the metadata impact --- a large
Charliecloud job may overwhelm a network filesystem.

