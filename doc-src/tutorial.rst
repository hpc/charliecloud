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

All the executables have decent help and can tell you what version of
Charliecloud you have (if not, please report a bug). For example::

  $ ch-run --help
  Usage: ch-run [OPTION...] NEWROOT CMD [ARG...]

  Run a command in a Charliecloud container.
  [...]
  $ ch-run --version
  0.2.0.4836ac1

The help text is also collected later in this documentation; see
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

We will use the following very simple Dockerfile:

.. literalinclude:: ../examples/hello/Dockerfile
   :language: docker

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

Charliecloud provides a convenience wrapper around :code:`docker build` that
works around some of its more irritating characteristics. In particular, it
passes through any HTTP proxy variables, and by default it uses the Dockerfile
in the current directory, rather than at the root of the Docker context
directory. (We will address the context directory later.)

The two arguments here are a tag for the Docker image and the context
directory, which in this case is the Charliecloud source code.

::

  $ ch-build -t hello ../..
  Sending build context to Docker daemon 8.105 MB
  Step 1 : FROM debian:jessie
   ---> ddf73f48a05d
  Step 2 : RUN apt-get update && apt-get install -y openssh-client
   ---> Running in beadfda45e4c
  [...]
   ---> 526e2ca75656
  Removing intermediate container beadfda45e4c
  Successfully built 526e2ca75656

:code:`ch-build` and many other Charliecloud commands wrap various
privileged :code:`docker` commands. Thus, you will be prompted for a password
to escalate as needed. Note however that most configurations of :code:`sudo`
don't require a password on every invocation, so just because you aren't
prompted doesn't mean privileged commands aren't running.

Share image and other standard Docker stuff
-------------------------------------------

If needed, the Docker image can be manipulated with standard Docker commands.
In particular, image sharing using a public or private Docker Hub repository
can be very useful.

::

  $ sudo docker images
  REPOSITORY  TAG     IMAGE ID      CREATED      SIZE
  debian      jessie  1742affe03b5  10 days ago  125.1 MB
  hello       latest  1742affe03b5  10 days ago  139.7 MB
  $ sudo docker push  # FIXME

Running the image with Docker is not generally useful, because Docker's
run-time environment is significantly different than Charliecloud's, but it
can have value when debugging Charliecloud.

::

  $ sudo docker run -it hello /bin/bash
  # ls /
  bin   dev  home  lib64  mnt  proc  run   srv  tmp  var
  boot  etc  lib   media  opt  root  sbin  sys  usr
  # exit
  exit

Flatten image
-------------

Next, we flatten the Docker image into a tarball, which is then a plain file
amenable to standard file manipulation commands. This tarball is placed in an
arbitrary directory, here :code:`/data`.

::

   $ ch-docker2tar hello /data
   57M /data/hello.tar.gz

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

   $ ch-tar2dir /data/hello.tar.gz /data/hello
   /data/hello unpacked ok

One potential gotcha is the tarball including special files such as devices.
Because :code:`tar` is running unprivileged, these will not be unpacked, and
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

  $ ch-run /data/hello -- echo hello
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
  $ ch-run /data/hello -- ls -l /proc/self/ns
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
  $ ch-run /data/hello -- stat -L --format='%i' /proc/self/ns/user
  4026532256

You can also run interactive commands, such as a shell::

  $ ch-run /data/hello -- /bin/bash
  $ stat -L --format='%i' /proc/self/ns/user
  4026532256
  $ exit

Be aware that wildcards in the :code:`ch-run` command are interpreted by the
host, not the container, unless protected. One workaround is to use a
sub-shell. For example::

  $ ls /usr/bin/oldfind
  ls: cannot access '/usr/bin/oldfind': No such file or directory
  $ ch-run /data/hello -- ls /usr/bin/oldfind
  /usr/bin/oldfind
  $ ls /usr/bin/oldf*
  ls: cannot access '/usr/bin/oldf*': No such file or directory
  $ ch-run /data/hello -- ls /usr/bin/oldf*
  ls: cannot access /usr/bin/oldf*: No such file or directory
  $ ch-run /data/hello -- sh -c 'ls /usr/bin/oldf*'
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
:code:`/sys`; :code:`/tmp`; Charliecloud's :code:`ch-ssh` command in
:code:`/usr/bin`; and the invoking user's home directory (for dotfiles).

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
  $ ch-run -d /data/foo0 -d /data/foo1 /data/hello bash
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
  $ ch-run /data/hello -- /bin/bash
  > stat -L --format='%i' /proc/self/ns/user
  4026532256
  > ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026531837

There are several ways to SSH to a remote note and run commands inside a
container. The simplest is to manually invoke :code:`ch-run` in the
:code:`ssh` command::

  $ ssh localhost ch-run /data/hello -- stat -L --format='%i' /proc/self/ns/user
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

  $ export CH_RUN_ARGS="/data/hello --"
  $ ch-ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026532256
  $ ch-ssh -t localhost /bin/bash
  > stat -L --format='%i' /proc/self/ns/user
  4026532256

:code:`ch-ssh` is available inside containers as well (in :code:`/usr/bin` via
bind-mount)::

  $ export CH_RUN_ARGS="/data/hello --"
  $ ch-run /data/hello /bin/bash
  > stat -L --format='%i' /proc/self/ns/user
  4026532256
  > ch-ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026532258

This also demonstrates that :code:`ch-run` does not alter your environment
variables.

.. warning::

   1. :code:`CH_RUN_ARGS` is interpreted very simply; the sole delimiter is
      spaces. It is not shell syntax. In particular, quotes and backslashes
      are not interpreted.

   2. Argument :code:`-t` is required for SSH to allocate a pseudo-TTY and
      thus convince your shell to be interactive. In the case of Bash,
      otherwise you'll get a shell that accepts commands but doesn't print
      prompts, among other other issues. (`Issue #2
      <https://github.com/hpc/charliecloud/issues/2>`_.)

A third may be to edit one's shell initialization scripts to check the command
line and :code:`exec(1)` :code:`ch-run` if appropriate. This is brittle but
avoids wrapping :code:`ssh` or altering its command line.

User and group IDs
------------------

Unlike Docker and some other container systems, Charliecloud tries to make the
container's users and groups look the same as the host's. (This is
accomplished by bind-mounting :code:`/etc/passwd` and :code:`/etc/group` into
the container.) For example::

  $ id -u
  901
  $ whoami
  reidpr
  $ ch-run /data/hello bash
  > id -u
  901
  > whoami
  reidpr

More specifically, the user namespace, when created without privileges as
Charliecloud does, lets you map any container UID to your host UID.
:code:`ch-run` implements this with the :code:`--uid` switch. So, for example,
you can tell Charliecloud you want to be root, and it will tell you that
you're root::

  $ ch-run --uid 0 /data/hello bash
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
  drwxr-xr-x 87 901 901 4096 Sep 28 12:12 /home/reidpr
  $ ls -ld ~
  drwxr-xr-x 87 reidpr reidpr 4096 Sep 28 12:12 /home/reidpr
  $ ch-run /data/hello bash
  > ls -nd ~
  drwxr-xr-x 87 901 901 4096 Sep 28 18:12 /home/reidpr
  > ls -ld ~
  drwxr-xr-x 87 reidpr reidpr 4096 Sep 28 18:12 /home/reidpr

But if :code:`--uid` is provided, things can seem odd. For example::

  $ ch-run --uid 0 /data/hello bash
  > ls -nd /home/reidpr
  drwxr-xr-x 87 0 901 4096 Sep 28 18:12 /home/reidpr
  > ls -ld /home/reidpr
  drwxr-xr-x 87 root reidpr 4096 Sep 28 18:12 /home/reidpr

This UID mapping can contain only one pair: an arbitrary container UID to your
effective UID on the host. Thus, all other users are unmapped, and they show
up as :code:`nobody`::

  $ ls -n /tmp/foo
  -rw-rw---- 1 902 902 0 Sep 28 15:40 /tmp/foo
  $ ls -l /tmp/foo
  -rw-rw---- 1 sig sig 0 Sep 28 15:40 /tmp/foo
  $ ch-run /data/hello bash
  > ls -n /tmp/foo
  -rw-rw---- 1 65534 65534 843 Sep 28 21:40 /tmp/foo
  > ls -l /tmp/foo
  -rw-rw---- 1 nobody nogroup 843 Sep 28 21:40 /tmp/foo

User namespaces have a similar mapping for GIDs, with the same limitation ---
exactly one arbitrary container GID maps to your effective *primary* GID. This
can lead to some strange-looking results, because only one of your GIDs can be
mapped in any given container. All the rest become :code:`nogroup`::

  $ id
  uid=901(reidpr) gid=901(reidpr) groups=901(reidpr),903(nerds),904(losers)
  $ ch-run /data/hello -- id
  uid=901(reidpr) gid=901(reidpr) groups=901(reidpr),65534(nogroup)
  $ ch-run --gid 903 /data/hello -- id
  uid=901(reidpr) gid=903(nerds) groups=903(nerds),65534(nogroup)

However, this doesn't affect access. The container process retains the same
GIDs from the host perspective, and as always, the host IDs are what control
access::

  $ ls -l /tmp/primary /tmp/supplemental
  -rw-rw---- 1 sig reidpr 0 Sep 28 15:47 /tmp/primary
  -rw-rw---- 1 sig nerds  0 Sep 28 15:48 /tmp/supplemental
  $ ch-run /data/hello bash
  > cat /tmp/primary > /dev/null
  > cat /tmp/supplemental > /dev/null

One area where functionality *is* reduced is that :code:`chgrp(1)` becomes
useless. Using an unmapped group or :code:`nogroup` fails, and using a mapped
group is a no-op because it's mapped back to the host GID::

  $ ls -l /tmp/bar
  rw-rw---- 1 reidpr reidpr 0 Sep 28 16:12 /tmp/bar
  $ ch-run /data/hello -- chgrp nerds /tmp/bar
  chgrp: changing group of '/tmp/bar': Invalid argument
  $ ch-run /data/hello -- chgrp nogroup /tmp/bar
  chgrp: changing group of '/tmp/bar': Invalid argument
  $ ch-run --gid 903 /data/hello -- chgrp nerds /tmp/bar
  $ ls -l /tmp/bar
  -rw-rw---- 1 reidpr reidpr 0 Sep 28 16:12 /tmp/bar

Workarounds include :code:`chgrp(1)` on the host or fastidious use of setgid
directories::

  $ mkdir /tmp/baz
  $ chgrp nerds /tmp/baz
  $ chmod 2770 /tmp/baz
  $ ls -ld /tmp/baz
  drwxrws--- 2 reidpr nerds 40 Sep 28 16:19 /tmp/baz
  $ ch-run /data/hello -- touch /tmp/baz/foo
  $ ls -l /tmp/baz/foo
  -rw-rw---- 1 reidpr nerds 0 Sep 28 16:21 /tmp/baz/foo

This concludes our discussion of how a Charliecloud container interacts with
its host. principal Charliecloud quirks. We next move on to installing
software.


Installing your own software
============================

This section covers four situations for making software available inside a
Charliecloud container:

  1. Third-party software installed into the image using a package manager.
  2. Third-party software compiled from source into the image.
  3. Your software installed into the image.
  4. Your software stored on the host but compiled in the container.

Many of Docker's `Best practices for writing Dockerfiles
<https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices>`_
apply to Charliecloud images as well, so you should be familiar with that
document.

.. note::

   Maybe you don't have to install the software at all. Is there already a
   trustable image on Docker Hub you can use as a base?

Third-party software via package manager
----------------------------------------

This approach is the simplest and fastest way to install stuff in your image.
The :code:`examples/hello` Dockerfile also seen above does this to install the
package :code:`openssh-client`:

.. literalinclude:: ../examples/hello/Dockerfile
   :language: docker
   :lines: 1-5

You can use distribution package managers such as :code:`apt-get`, as
demonstrated above, or others, such as :code:`pip` for Python modules.

Be aware that the software will be downloaded anew each time you build the
image, unless you add an HTTP cache, which is out of scope of this tutorial.

Third-party software compiled from source
-----------------------------------------

Under this method, one uses :code:`RUN` commands to fetch the desired software
using :code:`curl` or :code:`wget`, compile it, and install. Our example does
this with two chained Dockerfiles. First, we build a basic Debian image
(:code:`test/Dockerfile.debian8`):

.. literalinclude:: ../test/Dockerfile.debian8
   :language: docker

Then, we add OpenMPI with :code:`test/Dockerfile.debian8openmpi`:

.. literalinclude:: ../test/Dockerfile.debian8openmpi
   :language: docker

So what is going on here?

1. Use the latest Debian, Jessie, as the base image.

2. Install a basic build system using the OS package manager.

3. Download and untar OpenMPI. Note the use of variables to make adjusting the
   URL and MPI version easier, as well as the explanation of why we're not
   using :code:`apt-get`, given that OpenMPI 1.10 is included in Debian.

4. Build and install OpenMPI. Note the :code:`getconf` trick to guess at an
   appropriate parallel build.

5. Clean up, in order to reduce the size of layers as well as the resulting
   Charliecloud tarball (:code:`rm -Rf`).

Finally, because it's a container image, you can be less tidy than you might
be on a normal system. For example, the above downloads and builds in
:code:`/` rather than :code:`/usr/local/src`, and it installs MPI into
:code:`/usr` rather than :code:`/usr/local`.

Your software stored in the image
---------------------------------

This method covers software provided by you that is included in the image.
This is recommended when your software is relatively stable or is not easily
available to users of your image, for example a library rather than simulation
code under active development.

The general approach is the same as installing third-party software from
source, but you use the :code:`COPY` instruction to transfer files from the
host filesystem (rather than the network via HTTP) to the image. For example,
the :code:`mpihello` Dockerfile extends :code:`debian8openmpi` with this
approach.

.. literalinclude:: ../examples/mpihello/Dockerfile
   :language: docker
   :lines: 1-6

These Dockerfile instructions:

1. Copy the host directory :code:`examples/mpihello` to the image at path
   :code:`/hello`. The host path is *relative to the context directory*;
   Docker builds have no access to the host filesystem outside the context
   directory. (This is so the Docker daemon can run on a different machine ---
   the context directory is tarred up and sent to the daemon, even if it's on
   the same machine.)

   The convention for the Charliecloud examples is that the build directory is
   always rooted at the top of the Charliecloud source code, but we could just
   as easily have provided the :code:`mpihello` directory. In that case, the
   source in :code:`COPY` would have been :code:`.`.

2. :code:`cd` to :code:`/hello`.

3. Compile our example. We include :code:`make clean` to remove any leftover
   build files, since they would be inappropriate inside the container.

Once the image is built, we can see the results. (Install the image into
:code:`/data` as outlined above, if you haven't already.)

::

  $ ch-run /data/mpihello -- ls -lh /hello
  total 32K
  -rw-rw---- 1 reidpr reidpr  908 Oct  4 15:52 Dockerfile
  -rw-rw---- 1 reidpr reidpr  157 Aug  5 22:37 Makefile
  -rw-rw---- 1 reidpr reidpr 1.2K Aug  5 22:37 README
  -rwxr-x--- 1 reidpr reidpr 9.5K Oct  4 15:58 hello
  -rw-rw---- 1 reidpr reidpr 1.4K Aug  5 22:37 hello.c
  -rwxrwx--- 1 reidpr reidpr  441 Aug  5 22:37 test.sh

We will revisit this image later.

Your software stored on the host
--------------------------------

This method leaves your software on the host but compiles it in the image.
This is recommended when your software is volatile or each image user needs a
different version, for example a simulation code under active development.

The general approach is to bind-mount the appropriate directory and then run
the build inside the container. We can re-use the :code:`mpihello` image to
demonstrate this.

::

  $ cd examples/mpihello
  $ ls -l
  total 20
  -rw-rw---- 1 reidpr reidpr  908 Oct  4 09:52 Dockerfile
  -rw-rw---- 1 reidpr reidpr 1431 Aug  5 16:37 hello.c
  -rw-rw---- 1 reidpr reidpr  157 Aug  5 16:37 Makefile
  -rw-rw---- 1 reidpr reidpr 1172 Aug  5 16:37 README
  -rwxrwx--- 1 reidpr reidpr  441 Aug  5 16:37 test.sh
  $ ch-run -d . /data/mpihello -- sh -c 'cd /mnt/0 && make'
  mpicc -std=gnu11 -Wall hello.c -o hello
  $ ls -l
  total 32
  -rw-rw---- 1 reidpr reidpr  908 Oct  4 09:52 Dockerfile
  -rwxrwx--- 1 reidpr reidpr 9632 Oct  4 10:43 hello
  -rw-rw---- 1 reidpr reidpr 1431 Aug  5 16:37 hello.c
  -rw-rw---- 1 reidpr reidpr  157 Aug  5 16:37 Makefile
  -rw-rw---- 1 reidpr reidpr 1172 Aug  5 16:37 README
  -rwxrwx--- 1 reidpr reidpr  441 Aug  5 16:37 test.sh

A common use case is to leave a container shell open in one terminal for
building, and then run using a separate container invoked from a different
terminal.


Your first single-node, multi-process jobs
==========================================

This is an important use case even for large-scale codes, when testing and
development happens at small scale but need to use an environment comparable
to large-scale runs.

This tutorial covers three approaches:

1. Processes are coordinated by the host, i.e., one process per container.

2. Processes are coordinated by the container, i.e., one container with
   multiple processes, using configuration files from the container.

3. Processes are coordinated by the container using configuration files from
   the host.

In order to test approach 1, you must install OpenMPI 1.10.\ *x* on the host. In
our experience, we have had success compiling from source with the same
options as in the Dockerfile, but there is probably more nuance to the match
than we've discovered.

Processes coordinated by host
-----------------------------

This approach does the forking and process coordination on the host. Each
process is spawned in its own container, and because Charliecloud introduces
minimal isolation, they can communicate almost as if they were running
directly on the host.

For example, using :code:`mpirun` and the :code:`mpihello` example above::

  $ mpirun --version
  mpirun (Open MPI) 1.10.2
  $ stat -L --format='%i' /proc/self/ns/user
  4026531837
  $ ch-run /data/mpihello -- mpirun --version
  mpirun (Open MPI) 1.10.4
  $ mpirun -np 4 ch-run /data/mpihello /hello/hello
  0: init ok cn001, 4 ranks, userns 4026532256
  1: init ok cn001, 4 ranks, userns 4026532267
  2: init ok cn001, 4 ranks, userns 4026532269
  3: init ok cn001, 4 ranks, userns 4026532271
  0: send/receive ok
  0: finalize ok

The advantage is that we can easily take advantage of host-specific things
such as configurations; the disadvantage is that it introduces a close
coupling between the host and container that can manifest in complex ways. For
example, while OpenMPI 1.10.2 worked with 1.10.4 above, both had to be
compiled with the same options. The OpenMPI 1.10.2 packages that come with
Ubuntu fail with "orte_util_nidmap_init failed" if run with the container
1.10.4.

Processes coordinated by container
----------------------------------

This approach starts a single container process, which then forks and
coordinates the parallel work. The advantage is that this approach is
completely independent of the host for dependency configuration and
installation; the disadvantage is that it cannot take advantage of any
host-specific things that might e.g. improve performance.

For example::

  $ ch-run /data/mpihello -- mpirun -np 4 /hello/hello
  0: init ok cn001, 4 ranks, userns 4026532256
  1: init ok cn001, 4 ranks, userns 4026532256
  2: init ok cn001, 4 ranks, userns 4026532256
  3: init ok cn001, 4 ranks, userns 4026532256
  0: send/receive ok
  0: finalize ok


Processes coordinated by container using host configuration
-----------------------------------------------------------

This approach is a middle ground. The use case is when there is some
host-specific configuration we want to use, but we don't want to install the
entire configured dependency on the host. It would be undesirable to copy this
configuration into the image, because that would reduce its portability.

The host configuration is communicated to the container by bind-mounting the
relevant directory and then pointing the application to it. There are a
variety of approaches. Some application or frameworks take command-line
parameters specifying the configuration path.

The approach used in our example is to set the configuration directory to
:code:`/mnt/0`. This is done in :code:`test/Dockerfile.debian8openmpi` with
the :code:`--sysconfdir` argument:

.. literalinclude:: ../test/Dockerfile.debian8openmpi
   :language: docker
   :lines: 23-29

The effect is that the image contains a default MPI configuration, but if you
specify a different configuration directory with :code:`-d`, that is
overmounted and used instead. For example::

  $ ch-run -d /usr/local/etc /data/mpihello -- mpirun -np 4 /hello/hello
  0: init ok cn001, 4 ranks, userns 4026532256
  1: init ok cn001, 4 ranks, userns 4026532256
  2: init ok cn001, 4 ranks, userns 4026532256
  3: init ok cn001, 4 ranks, userns 4026532256
  0: send/receive ok
  0: finalize ok

A similar approach creates a dangling symlink with :code:`RUN` that is
resolved when the appropriate host directory is bind-mounted into
:code:`/mnt`.


Your first multi-node jobs
==========================

This section assumes that you are using a MOAB/SLURM cluster with a working
OpenMPI 1.10.\ *x* installation and some type of node-local storage. A
:code:`tmpfs` will suffice, and we use :code:`/tmp` for this tutorial, but
it's best to use something else to avoid confusion with circular mounts
(recall that :code:`/tmp` is shared by the container and host).

We cover three cases:

1. The MPI hello world example above, run interactively, with the host
   coordinating.

2. Same, non-interactive.

3. An Apache Spark example, run interactively.

4. Same, non-interactive.

We think that container-coordinated MPI jobs will also work, but we haven't
worked out how to do this yet. (See issue #5.)

.. note::

   The image directory is mounted read-only, so it can be shared by multiple
   Charliecloud containers in the same or different jobs.

.. warning::

   The image can reside on any filesystem, but be aware of metadata impact. A
   non-trivial Charliecloud job may overwhelm a network filesystem, earning
   you the ire of your sysadmins and colleagues.

Interactive MPI hello world
---------------------------

First, obtain an interactive allocation of nodes. This tutorial assumes an
allocation of 4 nodes (but any number should work) and an interactive shell on
one of those nodes. For example::

  $ msub -I -l nodes=4

We also need OpenMPI 1.10.\ *x* available::

  $ mpirun --version
  mpirun (Open MPI) 1.10.3

The next step is to distribute the image to the compute nodes, which we assume
is in the home directory. To do so, we run one instance of :code:`ch-tar2dir`
on each node::

  $ cd
  $ mpirun -pernode ch-tar2dir ./mpihello.tar.gz /tmp/mpihello
  App launch reported: 4 (out of 4) daemons - 3 (out of 4) procs
  creating new image /tmp/mpihello
  creating new image /tmp/mpihello
  creating new image /tmp/mpihello
  creating new image /tmp/mpihello
  /tmp/mpihello unpacked ok
  /tmp/mpihello unpacked ok
  /tmp/mpihello unpacked ok
  /tmp/mpihello unpacked ok

We can now activate the image and run our program::

  $ mpirun ch-run /tmp/mpihello -- /hello/hello
  App launch reported: 4 (out of 4) daemons - 48 (out of 64) procs
  2: init ok cn001.localdomain, 64 ranks, userns 4026532567
  4: init ok cn001.localdomain, 64 ranks, userns 4026532571
  8: init ok cn001.localdomain, 64 ranks, userns 4026532579
  [...]
  45: init ok cn003.localdomain, 64 ranks, userns 4026532589
  17: init ok cn002.localdomain, 64 ranks, userns 4026532565
  55: init ok cn004.localdomain, 64 ranks, userns 4026532577
  0: send/receive ok
  0: finalize ok

Success!

Non-interactive MPI hello world
-------------------------------

Production jobs are normally run non-interactively, via submission of a job
script that runs when resources are available, placing output into a file.

The MPI hello world example includes such a script:

.. literalinclude:: ../examples/mpihello/moab.sh

Note that this script both unpacks the image and runs it.

Submit it with something like::

  $ msub -l nodes=4 ~/charliecloud/examples/mpihello/moab.sh
  86753

When the job is complete, look at the output::

  $ cat slurm-86753.out
  host:      mpirun (Open MPI) 1.10.3
  container: mpirun (Open MPI) 1.10.4
  App launch reported: 4 (out of 4) daemons - 48 (out of 64) procs
  8: init ok cn001.localdomain, 64 ranks, userns 4026532579
  0: init ok cn001.localdomain, 64 ranks, userns 4026532564
  2: init ok cn001.localdomain, 64 ranks, userns 4026532568
  [...]
  61: init ok cn004.localdomain, 64 ranks, userns 4026532589
  63: init ok cn004.localdomain, 64 ranks, userns 4026532593
  54: init ok cn004.localdomain, 64 ranks, userns 4026532575
  0: send/receive ok
  0: finalize ok

Success!

Interactive Apache Spark
------------------------

This example is in :code:`examples/spark`. Build a tarball and upload it to
your cluster.

Once you have an interactive job, unpack the tarball.

::

  $ mpirun -pernode ch-tar2dir ./$USER.spark.tar.gz /tmp/spark

We need to first create a basic configuration directory for Spark, as the
defaults in the Dockerfile are insufficient. (For real jobs, you'll want to
also configure performance parameters such as memory use; see `the
documentation <http://spark.apache.org/docs/latest/configuration.html>`_.)
First::

  $ mkdir ~/sparkconf

Next, we set some environment variables. In the directory above, create a file
containing something like the following. Edit to match your configuration; in
particular, use local disks instead of :code:`/tmp` if you have them.
:code:`spark-env.sh`::

  SPARK_LOCAL_DIRS=/tmp
  SPARK_LOG_DIR=/home/$USER/sparklog
  SPARK_WORKER_DIR=/tmp
  SPARK_LOCAL_IP=$(  ip -o -f inet addr show dev eth0 \
                   | sed -r 's/^.+inet ([0-9.]+).+/\1/')
  SPARK_MASTER_HOST=$SPARK_LOCAL_IP

This is a shell script, so you can include code to set variables, as we do to
select the IP address of the right interface.

Other configuration variables are called "Spark properties" and go in a
different file. Change the secret to something known only to you.
:code:`spark-defaults.conf`::

  spark.authenticate true
  spark.authenticate.secret CHANGEME

We can now start the Spark master::

  $ ch-run -d ~/sparkconf /tmp/spark -- /spark/sbin/start-master.sh

If you can see the node with a web browser, browse to
:code:`http://$SPARK_LOCAL_IP:8080` for the Spark master web interface.
Because this capability varies, the tutorial does not depend on it, but it can
be informative. Refresh after each key step below.

The Spark workers need to know how to reach the master. This is via a URL; you
can construct it from your knowledge of :code:`$SPARK_LOCAL_IP`, or consult
the web interface. For example::

  $ MASTER_URL=spark://10.8.8.1:7077

Next, start one worker on each compute node. This is a little ugly;
:code:`mpirun` will wait until everything is finished before returning, but we
want to start the workers in the background, so we add :code:`&` and introduce
a race condition. (:code:`srun` has different, even less helpful behavior: it
kills the worker as soon as it goes into the background.)

::

  $ mpirun -pernode ch-run -d ~/sparkconf /tmp/spark -- \
    /spark/sbin/start-slave.sh $MASTER_URL &

We can now start an interactive shell to do some Spark computing::

  $ ch-run -d ~/sparkconf /tmp/spark -- /spark/bin/pyspark --master $MASTER_URL

Let's use this shell to estimate 𝜋 (this is adapted from one of the Spark
`examples <http://spark.apache.org/examples.html>`_):

.. code-block:: pycon

  >>> import operator
  >>> import random
  >>>
  >>> def sample(p):
  ...    (x, y) = (random.random(), random.random())
  ...    return 1 if x*x + y*y < 1 else 0
  ...
  >>> SAMPLE_CT = int(2e8)
  >>> ct = sc.parallelize(xrange(0, SAMPLE_CT)) \
  ...        .map(sample) \
  ...        .reduce(operator.add)
  >>> 4.0*ct/SAMPLE_CT
  3.14109824

(Type Control-D to exit.)

We can also submit jobs to the Spark cluster. This one runs the same example
as included with the Spark source code. (The voluminous logging output is
omitted.)

::

  $ ch-run -d ~/sparkconf /tmp/spark -- \
    /spark/bin/spark-submit --master $MASTER_URL \
    /spark/examples/src/main/python/pi.py 1024
  [...]
  Pi is roughly 3.141211
  [...]

Finally, we shut down the Spark cluster. This isn't strictly necessary, as
SLURM will kill everything when exit the allocation, but it's good hygiene::

  $ mpirun -pernode ch-run -d ~/sparkconf /tmp/spark /spark/sbin/stop-slave.sh
  $ ch-run -d ~/sparkconf /tmp/spark /spark/sbin/stop-master.sh

Success! Next, we'll run a similar job non-interactively.

Non-interactive Apache Spark
----------------------------

We'll re-use much of the above, including the configuration we created, to run
the same computation non-interactively. Here is the Moab script:

.. literalinclude:: ../examples/spark/moab.sh

There are four basic steps:

1. Unpack the image.
2. Start a Spark cluster.
3. Run our computation.
4. Stop the Spark cluster.

Submit like so::

  $ msub -l nodes=4 ~/charliecloud/examples/spark/moab.sh

Output::

  $ fgrep 'Pi is' slurm-86754.out
  Pi is roughly 3.141393

Success! (to four significant digits)
