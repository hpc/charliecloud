Tutorial
********

This tutorial will teach you how to create and run Charliecloud images, using
both examples included with the source code as well as new ones you create
from scratch.

This tutorial assumes that: (a) Charliecloud is in your path, including
Charliecloud's fully unprivileged image builder :code:`ch-image` and (b) the
Charliecloud source code is available at :code:`/usr/local/src/charliecloud`.
(If you wish to use Docker to build images, see the :ref:`FAQ
<faq_building-with-docker>`.)

.. contents::
   :depth: 2
   :local:

.. note::

   Shell sessions throughout this documentation will use the prompt :code:`$`
   to indicate commands executed natively on the host and :code:`>` for
   commands executed in a container.


90 seconds to Charliecloud
==========================

This section is for the impatient. It shows you how to quickly build and run a
“hello world” Charliecloud container. If you like what you see, then proceed
with the rest of the tutorial to understand what is happening and how to use
Charliecloud for your own applications.

Using a SquashFS image
----------------------

The preferred workflow uses our internal SquashFS mounting code. Your sysadmin
should be able to tell you if this is linked in.

::

  $ cd /usr/local/share/doc/charliecloud/examples/hello
  $ ch-image build --force .
  inferred image name: hello
  [...]
  grown in 4 instructions: hello
  $ ch-convert hello /var/tmp/hello.sqfs
  input:   ch-image  hello
  output:  squash    /var/tmp/hello.sqfs
  packing ...
  Parallel mksquashfs: Using 8 processors
  Creating 4.0 filesystem on /var/tmp/hello.sqfs, block size 65536.
  [=============================================|] 10411/10411 100%
  [...]
  done
  $ ch-run /var/tmp/hello.sqfs -- echo "I’m in a container"
  I’m in a container

Using a directory images
------------------------

If not, you can create image in plain directory format instead::

  $ cd /usr/local/share/doc/charliecloud/examples/hello
  $ ch-image build --force .
  inferred image name: hello
  [...]
  grown in 4 instructions: hello
  $ ch-convert hello /var/tmp/hello
  input:   ch-image  hello
  output:  dir       /var/tmp/hello
  exporting ...
  done
  $ ch-run /var/tmp/hello -- echo "I’m in a container"
  I’m in a container

.. note::

   You can run perfectly well out of :code:`/tmp`, but because it is
   bind-mounted automatically, the image root will then appear in multiple
   locations in the container’s filesystem tree. This can cause confusion for
   both users and programs.

Getting help
============

All the executables have decent help and can tell you what version of
Charliecloud you have (if not, please report a bug). For example::

  $ ch-run --help
  Usage: ch-run [OPTION...] NEWROOT CMD [ARG...]

  Run a command in a Charliecloud container.
  [...]
  $ ch-run --version
  0.26

Man pages for all commands are provided in this documentation (see table of
contents at left) as well as via :code:`man(1)`.


Pull an image
=============

To start, let’s obtain a container image that someone else has already built.
The containery way to do this is the pull operation, which means to move an
image from a remote repository into local storage of some kind.

First, browse the Docker Hub repository of `official AlmaLinux images
<https://hub.docker.com/_/almalinux>`_. Note the list of tags; this is a
partial list of image versions that are available. We’ll use the tag
“:code:`8`”.

Use the Charliecloud program :code:`ch-image` to pull this image to a
directory::

   $ ch-image pull almalinux:8
   pulling image:    almalinux:8
   requesting arch:  amd64
   manifest list: downloading: 100%
   manifest: downloading: 100%
   config: downloading: 100%
   layer 1/1: 3239c63: downloading: 68.2/68.2 MiB (100%)
   pulled image: adding to build cache
   flattening image
   layer 1/1: 3239c63: listing
   validating tarball members
   layer 1/1: 3239c63: changed 42 absolute symbolic and/or hard links to relative
   resolving whiteouts
   layer 1/1: 3239c63: extracting
   image arch: amd64
   done
   $ ch-image list
   almalinux:8

Images come in lots of different formats; :code:`ch-run` can use directories
and SquashFS archives. For this example, we’ll use SquashFS. We use the
command :code:`ch-convert` to create a SquashFS image from :code:`ch-image`’s
internal storage directory, then run it::

   $ ch-convert almalinux:8 almalinux.sqfs
   $ ch-run almalinux.sqfs -- /bin/bash
   > pwd
   /
   > ls
   bin  ch  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run
   sbin  srv  sys  tmp  usr  var
   > cat /etc/redhat-release
   AlmaLinux release 8.7 (Stone Smilodon)
   > exit

What does this command do?

  1. Create a SquashFS-format image (:code:`ch-convert ...`).

  2. Create a container using that image (:code:`ch-run almalinux.sqfs`).

  3. Stop processing :code:`ch-run` options (:code:`--`). (This is
     standard notation for UNIX command line programs.)

  4. Run the program :code:`/bin/bash` inside the container, which starts an
     interactive shell, where we enter a few commands and then exit, returning
     to the host.

Containers are not special
==========================

Many folks would like you to believe that containers are magic and special
(especially if they want to sell you their container product). This is not the
case. To demonstrate, we’ll create a working container image using standard
UNIX tools.

Many Linux distributions provide tarballs containing installed based images,
including Alpine. We can use these in Charliecloud directly::

  $ wget -O alpine.tar.gz 'https://github.com/alpinelinux/docker-alpine/blob/v3.16/x86_64/alpine-minirootfs-3.16.3-x86_64.tar.gz?raw=true'
  $ tar tf alpine.tar.gz | head -10
  ./
  ./root/
  ./var/
  ./var/log/
  ./var/lock/
  ./var/lock/subsys/
  ./var/spool/
  ./var/spool/cron/
  ./var/spool/cron/crontabs
  ./var/spool/mail

This tarball is what’s called a “tarbomb”, so we need to provide an enclosing
directory to avoid making a mess::

  $ mkdir alpine
  $ cd alpine
  $ tar xf ../alpine.tar.gz
  $ ls
  bin  etc   lib    mnt  proc  run   srv  tmp  var
  dev  home  media  opt  root  sbin  sys  usr
  $ du -sh
  5.6M	.
  $ cd ..

Now, run a shell in the container! (Note that base Alpine does not have Bash.)

::

  $ ch-run ./alpine -- /bin/sh
  > pwd
  /
  > ls
  bin    etc    lib    mnt    proc   run    srv    tmp    var
  dev    home   media  opt    root   sbin   sys    usr
  > cat /etc/alpine-release
  3.16.3
  > exit

.. warning::

   Generally, you should avoid directory-format images on shared filesystems
   such as NFS and Lustre, in favor of local storage such as :code:`tmpfs` and
   local hard disks. This will yield better performance for you and anyone
   else on the shared filesystem. In contrast, SquashFS images should work
   fine on shared filesystems.


Build from Dockerfile
=====================

The other containery way to get an image is the build operation. This
interprets a recipe, usually a Dockerfile, to create an image and place it
into builder storage. We can then extract the image from builder storage to a
directory and run it.

Charliecloud supports arbitrary image builders. In this tutorial, we use
:code:`ch-image`, which comes with Charliecloud, but you can also use others,
e.g. Docker or Podman. :code:`ch-image` is a big deal because it is completely
unprivileged. Other builders typically run as root or require setuid root
helper programs; this raises a number of security questions.

We’ll write a “Hello World” Python program and run it within a container we
specify with a Dockerfile. Set up a directory to work in::

  $ mkdir hello.src
  $ cd hello.src

Type in the following program as :code:`hello.py` using your least favorite
editor:

.. code-block:: python

   #!/usr/bin/python3

   print("Hello World!")

Next, create a file called :code:`Dockerfile` and type in the following
recipe:

.. code-block:: docker

   FROM almalinux:8
   RUN yum -y install python36
   COPY ./hello.py /
   RUN chmod 755 /hello.py

These four instructions say:

  1. :code:`FROM`: We are extending the :code:`almalinux:8` *base image*.

  2. :code:`RUN`: Install the :code:`python36` RPM package, which we need for
     our Hello World program.

  3. :code:`COPY`: Copy the file :code:`hello.py` we just made to the root
     directory of the image. In the source argument, the path is relative to
     the *context directory*, which we’ll see more of below.

  4. :code:`RUN`: Make that file executable.

Let’s build this image::

  $ ch-image build -t hello -f Dockerfile .
    1. FROM almalinux:8
  [...]
    4. RUN chmod 755 /hello.py
  grown in 4 instructions: hello

This command says:

  1. Build (:code:`ch-image build`) an image named (a.k.a. tagged) “hello”
     (:code:`-t hello`).

  2. Use the Dockerfile called “Dockerfile” (:code:`-f Dockerfile`).

  3. Use the current directory as the context directory (:code:`.`).

Now, list the images :code:`ch-image` knows about::

  $ ch-image list
  almalinux:8
  hello

And run the image we just made::

  $ cd ..
  $ ch-convert hello hello.sqfs
  $ ch-run hello.sqfs -- /hello.py
  Hello World!

This time, we’ve run our application directly rather than starting an
interactive shell.


Push an image
=============

The containery way to share your images is by pushing them to a container
registry. In this section, we will set up a registry on GitLab and push the
hello image to that registry, then pull it back to compare.

Destination setup
-----------------

Create a private container registry:

  1. Browse to https://gitlab.com (or any other GitLab instance).

  2. Log in. You should end up on your *Projects* page.

  3. Click *New project* then *Create blank project*.

  4. Name your project “:code:`test-registry`”. Leave *Visibility Level* at
     *Private*. Click *Create project*. You should end up at your project’s
     main page.

  5. At left, choose *Settings* (the gear icon) → *General*, then *Visibility,
     project features, permissions*. Enable *Container registry*, then click
     *Save changes*.

  6. At left, choose Packages & Registries (the box icon) → Container
     registry. You should see the message “There are no container images
     stored for this project”.

At this point, we have a container registry set up, and we need to teach
:code:`ch-image` how to log into it. On :code:`gitlab.com` and some other
instances, you can use your GitLab password. However, GitLab has a thing
called a *personal access token* (PAT) that can be used no matter how you log
into the GitLab web app. To create one:

  1. Click on your avatar at the top right. Choose *Edit Profile*.

  2. At left, choose *Access Tokens* (the three-pin plug icon).

  3. Type in the name “:code:`registry`”. Tick the boxes *read_registry* and
     *write_registry*. Click *Create personal access token*.

  4. Your PAT will be displayed at the top of the result page under *Your new
     personal access token*. Copy this string and store it somewhere safe &
     policy-compliant for your organization. (Also, you can revoke it at the
     end of the tutorial if you like.)

Push
----

We can now use :code:`ch-image push` to push the image to GitLab. (Note that
the tagging step you would need for Docker is unnecessary here, because we can
just specify a destination reference at push time.)

For the gitlab path, it you put your registry in a group update the path
accordingly. For example, if I put my container registry in group called 
containers the path would be:
:code:`gitlab.com/$USER/containers/test-registry/hello:latest`.

When you are prompted for credentials, enter your GitLab username and
copy-paste the PAT you created earlier (or enter your password). You will need
to substitute your GitLab username for :code:`$USER` below.

::

  $ ch-image push hello gitlab.com:5050/$USER/test-registry/hello:latest
  pushing image:   hello
  destination:     gitlab.com:5050/$USER/test-registry/hello:latest
  layer 1/1: gathering
  layer 1/1: preparing
  preparing metadata
  starting upload
  layer 1/1: bca515d: checking if already in repository

  Username: $USER
  Password:
  layer 1/1: bca515d: not present, uploading: 139.8/139.8 MiB(100%
  config: f969909: checking if already in repository
  config: f969909: not present, uploading
  manifest: uploading
  cleaning up
  done

Go back to your container registry page. You should see your image listed now!

Pull and compare
----------------

Let’s pull that image and see how it looks::

  $ ch-image pull --auth registry.gitlab.com/$USER/test-registry/hello:latest hello.2
  pulling image:   gitlab.com:5050/$USER/test-registry/hello:latest
  destination:     hello.2
  [...]
  $ ch-image list
  almalinux:8
  hello
  hello.2
  $ ch-image convert hello.2 ./hello.2
  $ ls ./hello.2
  bin    etc    lib    mnt    proc   run    srv    tmp    var
  dev    home   media  opt    root   sbin   sys    usr

MPI Hello World
===============

Pull base image
---------------

we'll use a simple parallel operation. First we need to pull the base image::

   ch-image pull mfisherman/openmpi openmpi

Build image
-----------

Create a new directory for this project, and within it following simple C program
called :code:`mpihello.c` (Note the program contains a bug; consider fixing it.)::

   #include <stdio.h>
   #include <mpi.h>

   int main (int argc, char **argv)
   {
      int msg, rank, rank_ct;

      MPI_Init(&argc, &argv);
      MPI_Comm_size(MPI_COMM_WORLD, &rank_ct);
      MPI_Comm_rank(MPI_COMM_WORLD, &rank);

      printf("hello from rank %d of %d\n", rank, rank_ct);

      if (rank == 0) {
         for (int i = 1; i < rank_ct; i++) {
            MPI_Send(&msg, 1, MPI_INT, i, 0, MPI_COMM_WORLD);
            printf("rank %d sent %d to rank %d\n", rank, msg, i);
         }
      } else {
         MPI_Recv(&msg, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
         printf("rank %d received %d from rank 0\n", rank, msg);
      }

      MPI_Finalize();
   }

Add the following :code:`Dockerfile`.::

   FROM openmpi
   RUN mkdir /hello
   WORKDIR /hello
   COPY mpihello.c .
   RUN mpicc -o mpihello mpihello.c .

The instruction :code:`WORKDIR` changes directories (the default working directory
within a Dockerfile is /).
Build::

   $ ls
   Dockerfile   mpihello.c
   $ ch-image build -t mpihello

Note that the default Dockerfile is :code:`./Dockerfile`; we can omit :code:`-f`.

We need to convert that directory image to a squashball so wer can run it on the compute
nodes::

   $ ch-convert mpihello mpihello.sqfs

Run the container
-----------------

We'll run this application interactively. One could also put similar steps in a Slurm batch
script.

First, obtain a two node allocation and install/load Charliecloud::

   $ salloc -N2 -t 1:00:00
   salloc: Granted job allocation 599518
   [...]

Put the application on all cores in your allocation::

   $ srun ch-covert ~/mpihello.sqfs /var/tmp/mpihello
   input:   tar       /users/$USER/mpihello.sqfs
   output:  dir       /var/tmp/mpihello
   analyzing ...
   input:   tar       /users/$USER/mpihello.sqfs
   output:  dir       /var/tmp/mpihello
   analyzing ...
   unpacking ...
   unpacking ...
   done
   done

Run the application on all cores in your allocation::

   $ srun -c1 ch-run /var/tmp/mpihello -- ./hello/mpihello
   hello from rank 1 of 71
   rank 1 received 0 from rank 0
   [...]
   hello from rank 63 of 71
   rank 1 received 0 from rank 62

Win!

Build cache
===========

:code:`ch-image` subcommands that create images, such as build and pull, can
use a build cache to speed repeated operations. That is, an image is created
by starting from the empty image and executing a sequence of instructions,
largely Dockerfile instructions but also some others like “pull” and “import”.
Some instructions are expensive to execute so it's often cheaper to retrieve
their results from cache instead.

Let’s set up this example by first resetting the build cache::

  $ ch-image build-cache --reset
  $ mkdir cache-test
  $ cd cache-test

Suppose we have a Dockerfile :code:`a.df`:

.. code-block:: docker

   FROM almalinux:8
   RUN sleep 2 && echo foo
   RUN sleep 2 && echo bar

On our first build, we get::

  $ ch-image build -t a -f a.df .
    1. FROM almalinux:8
  [ ... pull chatter omitted ... ]
    2. RUN echo foo
  copying image ...
  foo
    3. RUN echo bar
  bar
  grown in 3 instructions: a

Note the dot after each instruction’s line number. This means that the
instruction was executed. You can also see this in the output of the two
:code:`echo` commands.

But on our second build, we get::

  $ ch-image build -t a -f a.df .
    1* FROM almalinux:8
    2* RUN sleep 2 && echo foo
    3* RUN sleep 2 && echo bar
  copying image …
  grown in 3 instructions: a

Here, instead of being executed, each instruction’s results were retrieved
from cache. Cache hit for each instruction is indicted by an asterisk
(“:code:`*`”) after the line number. Even for such a small and short
Dockerfile, this build is noticeably faster than the first.

Let’s also try a second, slightly different Dockerfile, :code:`b.df`. Note the
first three instructions are the same, but the third is different.

.. code-block:: docker

   FROM almalinux:8
   RUN sleep 2 && echo foo
   RUN sleep 2 && echo qux

Build it::

  $ ch-image build -t b -f b.df .
    1* FROM almalinux:8
    2* RUN sleep 2 && echo foo
    3. RUN sleep 2 && echo qux
  copying image
  qux
  grown in 3 instructions: b

Here, the first two instructions are hits from the first Dockerfile, but the
third is a miss, so Charliecloud retrieves that state and continues building.

Finally, inspect the cache::

  $ ch-image build-cache --tree
  *  (b) RUN sleep 2 && echo qux
  | *  (a) RUN sleep 2 && echo bar
  |/
  *  RUN sleep 2 && echo foo
  *  (almalinux:8) PULL almalinux:8
  *  (HEAD -> root) ROOT

  named images:    4
  state IDs:       5
  commits:         5
  files:         317
  disk used:       3 MiB

Here there are four named images: :code:`a` and :code:`b` that we built, the
base image :code:`almalinux:8`, and the empty base of everything :code:`ROOT`.
Also note that :code:`a` and :code:`b` diverge after the last common
instruction :code:`RUN sleep 2 && echo foo`.


Appendices
==========

Namespaces with :code:`unshare(1)`
----------------------------------

:code:`unshare(1)` is a shell command that comes with most new-ish Linux
distributions in the :code:`util-linux` package. We will use it to explore a
little about how namespaces, which are the basis of containers, work.

Identifying the current namespaces
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are several kinds of namespaces, and every process is always in one
namespace of each kind. Namespaces within each kind form a tree. Every
namespace has an ID number, which you can see in :code:`/proc` with some magic
symlinks::

   $ ls -l /proc/self/ns
   total 0
   lrwxrwxrwx 1 charlie charlie 0 Mar 31 16:44 cgroup -> 'cgroup:[4026531835]'
   lrwxrwxrwx 1 charlie charlie 0 Mar 31 16:44 ipc -> 'ipc:[4026531839]'
   lrwxrwxrwx 1 charlie charlie 0 Mar 31 16:44 mnt -> 'mnt:[4026531840]'
   lrwxrwxrwx 1 charlie charlie 0 Mar 31 16:44 net -> 'net:[4026531992]'
   lrwxrwxrwx 1 charlie charlie 0 Mar 31 16:44 pid -> 'pid:[4026531836]'
   lrwxrwxrwx 1 charlie charlie 0 Mar 31 16:44 pid_for_children -> 'pid:[4026531836]'
   lrwxrwxrwx 1 charlie charlie 0 Mar 31 16:44 user -> 'user:[4026531837]'
   lrwxrwxrwx 1 charlie charlie 0 Mar 31 16:44 uts -> 'uts:[4026531838]'

Let’s start a new shell with different user and mount namespaces. Note how the
ID numbers change for these two, but not the others.

::

   $ unshare --user --mount
   > ls -l /proc/self/ns | tee inside.txt
   total 0
   lrwxrwxrwx 1 nobody nogroup 0 Mar 31 16:46 cgroup -> 'cgroup:[4026531835]'
   lrwxrwxrwx 1 nobody nogroup 0 Mar 31 16:46 ipc -> 'ipc:[4026531839]'
   lrwxrwxrwx 1 nobody nogroup 0 Mar 31 16:46 mnt -> 'mnt:[4026532733]'
   lrwxrwxrwx 1 nobody nogroup 0 Mar 31 16:46 net -> 'net:[4026531992]'
   lrwxrwxrwx 1 nobody nogroup 0 Mar 31 16:46 pid -> 'pid:[4026531836]'
   lrwxrwxrwx 1 nobody nogroup 0 Mar 31 16:46 pid_for_children -> 'pid:[4026531836]'
   lrwxrwxrwx 1 nobody nogroup 0 Mar 31 16:46 user -> 'user:[4026532732]'
   lrwxrwxrwx 1 nobody nogroup 0 Mar 31 16:46 uts -> 'uts:[4026531838]'
   > exit

These IDs are available both in the name and inode number of the magic symlink
target::

   $ stat -L /proc/self/ns/user
     File: /proc/self/ns/user
     Size: 0         	Blocks: 0          IO Block: 4096   regular empty file
   Device: 4h/4d	Inode: 4026531837  Links: 1
   Access: (0444/-r--r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
   Access: 2022-12-16 10:56:54.916459868 -0700
   Modify: 2022-12-16 10:56:54.916459868 -0700
   Change: 2022-12-16 10:56:54.916459868 -0700
    Birth: -
   $ unshare --user --mount -- stat -L /proc/self/ns/user
     File: /proc/self/ns/user
     Size: 0         	Blocks: 0          IO Block: 4096   regular empty file
   Device: 4h/4d	Inode: 4026532565  Links: 1
   Access: (0444/-r--r--r--)  Uid: (65534/  nobody)   Gid: (65534/ nogroup)
   Access: 2022-12-16 10:57:07.136561077 -0700
   Modify: 2022-12-16 10:57:07.136561077 -0700
   Change: 2022-12-16 10:57:07.136561077 -0700
    Birth: -

The user namespace
~~~~~~~~~~~~~~~~~~

Unprivileged user namespaces let you map your effective user id (UID) to any
UID inside the namespace, and your effective group ID (GID) to any GID. Let’s
try it. First, who are we?

::

  $ id
  uid=1000(charlie) gid=1000(charlie)
  groups=1000(charlie),24(cdrom),25(floppy),27(sudo),29(audio)

This shows our user (1000 :code:`charlie`), our primary group (1000
:code:`charlie`), and a bunch of supplementary groups.

Let’s start a user namespace, mapping our UID to 0 (:code:`root`) and our GID
to 0 (:code:`root`)::

  $ unshare --user --map-root-user
  > id
  uid=0(root) gid=0(root) groups=0(root),65534(nogroup)

This shows that our UID inside the container is 0, our GID is 0, and all
supplementary groups have collapsed into 65534:code:`nogroup`, because they
are unmapped inside the namespace. (If :code:`id` complains about not finding
names for IDs, just ignore it.)

We are root!! Let's try something sneaky!!!

::

  > cat /etc/shadow
  cat: /etc/shadow: Permission denied

Drat! The kernel followed the UID map outside the namespace and used that for
access control; i.e., we are still acting as us, a normal unprivileged user
who cannot read :code:`/etc/shadow`. Something else interesting::

  > ls -l /etc/shadow
  -rw-r----- 1 nobody nogroup 2151 Feb 10 11:51 /etc/shadow
  > exit

This shows up as :code:`nobody:nogroup` because UID 0 and GID 0 outside the
container are not mapped to anything inside (i.e., they are *unmapped*).

The mount namespace
~~~~~~~~~~~~~~~~~~~

This namespace lets us set up an independent filesystem tree. For this
exercise, you will need two terminals.

In Terminal 1, set up namespaces and mount a new tmpfs over your home
directory::

  $ unshare --mount --user
  > mount -t tmpfs none /home/charlie
  mount: only root can use "--types" option

Wait! What!? The problem now is that you still need to be root inside the
container to use the :code:`mount(2)` system call. Try again::

  $ unshare --mount --user --map-root-user
  > mount -t tmpfs none /home/charlie
  > mount | fgrep /home/charlie
  none on /home/charlie type tmpfs (rw,relatime,uid=1000,gid=1000)
  > touch /home/charlie/foo
  > ls /home/charlie
  foo

In Terminal 2, which is not in the container, note how the mount doesn’t show
up in :code:`mount` output and the files you created are not present::

  $ ls /home/charlie
  articles.txt             flu-index.tsv           perms_test
  [...]
  $ mount | fgrep /home/charlie
  $

Exit the container in Terminal 1::

  > exit

Namespaces in Charliecloud
--------------------------

Let’s revisit the symlinks in :code:`/proc`, but this time with Charliecloud::

  $ ls -l /proc/self/ns
  total 0
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 11:24 ipc -> ipc:[4026531839]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 11:24 mnt -> mnt:[4026531840]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 11:24 net -> net:[4026531969]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 11:24 pid -> pid:[4026531836]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 11:24 user -> user:[4026531837]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 11:24 uts -> uts:[4026531838]
  $ ch-run /var/tmp/hello -- ls -l /proc/self/ns
  total 0
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 17:34 ipc -> ipc:[4026531839]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 17:34 mnt -> mnt:[4026532257]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 17:34 net -> net:[4026531969]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 17:34 pid -> pid:[4026531836]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 17:34 user -> user:[4026532256]
  lrwxrwxrwx 1 charlie charlie 0 Sep 28 17:34 uts -> uts:[4026531838]

The container has different mount (:code:`mnt`) and user (:code:`user`)
namespaces, but the rest of the namespaces are shared with the host. This
highlights Charliecloud's focus on functionality (make your UDSS run), rather
than isolation (protect the host from your UDSS).

Normally, each invocation of :code:`ch-run` creates a new container, so if you
have multiple simultaneous invocations, they will not share containers. In
some cases this can cause problems with MPI programs. However, there is an
option :code:`--join` that can solve them; see the :ref:`FAQ <faq_join>` for
details.

All you need is Bash
--------------------

In this exercise, we’ll use shell commands to create minimal container image
with a working copy of Bash, and that’s all. To do so, we need to set up a
directory with the Bash binary, the shared libraries it uses, and a few other
hooks needed by Charliecloud.

**Important:** Your Bash is almost certainly linked differently than described
below. Use the paths from your terminal, not this tutorial. Adjust the steps
below as needed. It will not work otherwise.

::

  $ ldd /bin/bash
      linux-vdso.so.1 (0x00007ffdafff2000)
      libtinfo.so.6 => /lib/x86_64-linux-gnu/libtinfo.so.6 (0x00007f6935cb6000)
      libdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007f6935cb1000)
      libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f6935af0000)
      /lib64/ld-linux-x86-64.so.2 (0x00007f6935e21000)
  $ ls -l /lib/x86_64-linux-gnu/libc.so.6
  lrwxrwxrwx 1 root root 12 May  1  2019 /lib/x86_64-linux-gnu/libc.so.6 -> libc-2.28.so

The shared libraries pointed to are symlinks, so we’ll use :code:`cp -L` ro
dereference them and copy the target files. :code:`linux-vdso.so.1` is a
kernel thing, not a shared library file, so we don’t copy that.

Set up the container::

  $ mkdir alluneed
  $ cd alluneed
  $ mkdir bin
  $ mkdir dev
  $ mkdir lib
  $ mkdir lib64
  $ mkdir lib/x86_64-linux-gnu
  $ mkdir proc
  $ mkdir sys
  $ mkdir tmp
  $ cp -pL /bin/bash ./bin
  $ cp -pL /lib/x86_64-linux-gnu/libtinfo.so.6 ./lib/x86_64-linux-gnu
  $ cp -pL /lib/x86_64-linux-gnu/libdl.so.2 ./lib/x86_64-linux-gnu
  $ cp -pL /lib/x86_64-linux-gnu/libc.so.6 ./lib/x86_64-linux-gnu
  $ cp -pL /lib64/ld-linux-x86-64.so.2 ./lib64/ld-linux-x86-64.so.2
  $ cd ..
  $ ls -lR alluneed
  ./alluneed:
  total 0
  drwxr-x--- 2 charlie charlie 60 Mar 31 17:15 bin
  drwxr-x--- 2 charlie charlie 40 Mar 31 17:26 dev
  drwxr-x--- 2 charlie charlie 80 Mar 31 17:27 etc
  drwxr-x--- 3 charlie charlie 60 Mar 31 17:17 lib
  drwxr-x--- 2 charlie charlie 60 Mar 31 17:19 lib64
  drwxr-x--- 2 charlie charlie 40 Mar 31 17:26 proc
  drwxr-x--- 2 charlie charlie 40 Mar 31 17:26 sys
  drwxr-x--- 2 charlie charlie 40 Mar 31 17:27 tmp

  ./alluneed/bin:
  total 1144
  -rwxr-xr-x 1 charlie charlie 1168776 Apr 17  2019 bash

  ./alluneed/dev:
  total 0

  ./alluneed/lib:
  total 0
  drwxr-x--- 2 charlie charlie 100 Mar 31 17:19 x86_64-linux-gnu

  ./alluneed/lib/x86_64-linux-gnu:
  total 1980
  -rwxr-xr-x 1 charlie charlie 1824496 May  1  2019 libc.so.6
  -rw-r--r-- 1 charlie charlie   14592 May  1  2019 libdl.so.2
  -rw-r--r-- 1 charlie charlie  183528 Nov  2 12:16 libtinfo.so.6

  ./alluneed/lib64:
  total 164
  -rwxr-xr-x 1 charlie charlie 165632 May  1  2019 ld-linux-x86-64.so.2

  ./alluneed/proc:
  total 0

  ./alluneed/sys:
  total 0

  ./alluneed/tmp:
  total 0

Next, start a container and run :code:`/bin/bash` within it. Option
:code:`--no-passwd` turns off some convenience features that this image isn’t
prepared for.

::

  $ ch-run --no-passwd ./alluneed -- /bin/bash
  > pwd
  /
  > echo "hello world"
  hello world
  > ls /
  bash: ls: command not found
  > echo *
  bin dev home lib lib64 proc sys tmp
  > exit

It’s not very useful since the only commands we have are Bash built-ins, but
it’s a container!


Interacting with the host
-------------------------

Charliecloud is not an isolation layer, so containers have full access to host
resources, with a few quirks. This section demonstrates how this works.

Filesystems
~~~~~~~~~~~

Charliecloud makes host directories available inside the container using bind
mounts, which is somewhat like a hard link in that it causes a file or
directory to appear in multiple places in the filesystem tree, but it is a
property of the running kernel rather than the filesystem.

Several host directories are always bind-mounted into the container. These
include system directories such as :code:`/dev`, :code:`/proc`, :code:`/sys`,
and :code:`/tmp`. Others can be requested with a command line option, e.g.
:code:`--home` bind-mounts the invoking user’s home directory.

Charliecloud uses recursive bind mounts, so for example if the host has a
variety of sub-filesystems under :code:`/sys`, as Ubuntu does, these will be
available in the container as well.

In addition to these, arbitrary user-specified directories can be added using
the :code:`--bind` or :code:`-b` switch. By default, mounts use the same path
as provided from the host. In the case of directory images, which are
writeable, the target mount directory will be automatically created before the
container is started::

  $ mkdir /var/tmp/foo0
  $ echo hello > /var/tmp/foo0/bar
  $ mkdir /var/tmp/foo1
  $ echo world > /var/tmp/foo1/bar
  $ ch-run -b /var/tmp/foo0 -b /var/tmp/foo1 /var/tmp/hello -- bash
  > cat /var/tmp/foo0/bar
  hello
  > cat /var/tmp/foo1/bar
  world

However, as SquashFS filesystems are read-only, in this case you must provide
a destination that already exists, like those created under :code:`/mnt`::

  $ mkdir /var/tmp/foo0
  $ echo hello > /var/tmp/foo0/bar
  $ mkdir /var/tmp/foo1
  $ echo world > /var/tmp/foo1/bar
  $ ch-run -b /var/tmp/foo0 -b /var/tmp/foo1 /var/tmp/hello -- bash
  ch-run[1184427]: error: can't mkdir: /var/tmp/hello/var/tmp/foo0: Read-only file system (ch_misc.c:142 30)
  $ ch-run -b /var/tmp/foo0:/mnt/0 -b /var/tmp/foo1:/mnt/1 /var/tmp/hello -- bash
  > ls /mnt
  0  1  2  3  4  5  6  7  8  9
  > cat /mnt/0/bar
  hello
  > cat /mnt/1/bar
  world

Network
~~~~~~~

Charliecloud containers share the host’s network namespace, so most network
things should be the same.

However, SSH is not aware of Charliecloud containers. If you SSH to a node
where Charliecloud is installed, you will get a shell on the host, not in a
container, even if :code:`ssh` was initiated from a container::

  $ stat -L --format='%i' /proc/self/ns/user
  4026531837
  $ ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026531837
  $ ch-run /var/tmp/hello.sqfs -- /bin/bash
  > stat -L --format='%i' /proc/self/ns/user
  4026532256
  > ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026531837

There are several ways to SSH to a remote node and run commands inside a
container. The simplest is to manually invoke :code:`ch-run` in the
:code:`ssh` command::

  $ ssh localhost ch-run /var/tmp/hello.sqfs -- stat -L --format='%i' /proc/self/ns/user
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

  $ export CH_RUN_ARGS="/var/tmp/hello.sqfs --"
  $ ch-ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026532256
  $ ch-ssh -t localhost /bin/bash
  > stat -L --format='%i' /proc/self/ns/user
  4026532256

:code:`ch-ssh` is available inside containers as well, in :code:`/usr/bin` via
bind-mount, if the image has a dummy file at :code:`/usr/bin/ch-ssh`::

  $ export CH_RUN_ARGS="/var/tmp/hello.sqfs --"
  $ ch-run /var/tmp/hello.sqfs -- /bin/bash
  > stat -L --format='%i' /proc/self/ns/user
  4026532256
  > ch-ssh localhost stat -L --format='%i' /proc/self/ns/user
  4026532258

This also demonstrates that :code:`ch-run` does not alter most environment
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

A third approach may be to edit one's shell initialization scripts to check
the command line and :code:`exec(1)` :code:`ch-run` if appropriate. This is
brittle but avoids wrapping :code:`ssh` or altering its command line.

User and group IDs
~~~~~~~~~~~~~~~~~~

Unlike Docker and some other container systems, Charliecloud tries to make the
container's users and groups look the same as the host’s. This is accomplished
by bind-mounting a custom :code:`/etc/passwd` and :code:`/etc/group` into the
container. For example::

  $ id -u
  901
  $ whoami
  charlie
  $ ch-run /var/tmp/hello.sqfs -- bash
  > id -u
  901
  > whoami
  charlie

More specifically, the user namespace, when created without privileges as
Charliecloud does, lets you map any container UID to your host UID.
:code:`ch-run` implements this with the :code:`--uid` switch. So, for example,
you can tell Charliecloud you want to be root, and it will tell you that
you’re root::

  $ ch-run --uid 0 /var/tmp/hello.sqfs -- bash
  > id -u
  0
  > whoami
  root

But, as shown above, this doesn’t get you anything useful, because the
container UID is mapped back to your UID on the host before permission checks
are applied::

  > dd if=/dev/mem of=/tmp/pwned
  dd: failed to open '/dev/mem': Permission denied

This mapping also affects how users are displayed. For example, if a file is
owned by you, your host UID will be mapped to your container UID, which is
then looked up in :code:`/etc/passwd` to determine the display name. In
typical usage without :code:`--uid`, this mapping is a no-op, so everything
looks normal::

  $ ls -nd ~
  drwxr-xr-x 87 901 901 4096 Sep 28 12:12 /home/charlie
  $ ls -ld ~
  drwxr-xr-x 87 charlie charlie 4096 Sep 28 12:12 /home/charlie
  $ ch-run /var/tmp/hello.sqfs -- bash
  > ls -nd ~
  drwxr-xr-x 87 901 901 4096 Sep 28 18:12 /home/charlie
  > ls -ld ~
  drwxr-xr-x 87 charlie charlie 4096 Sep 28 18:12 /home/charlie

But if :code:`--uid` is provided, things can seem odd. For example::

  $ ch-run --uid 0 /var/tmp/hello.sqfs -- bash
  > ls -nd /home/charlie
  drwxr-xr-x 87 0 901 4096 Sep 28 18:12 /home/charlie
  > ls -ld /home/charlie
  drwxr-xr-x 87 root charlie 4096 Sep 28 18:12 /home/charlie

This UID mapping can contain only one pair: an arbitrary container UID to your
effective UID on the host. Thus, all other users are unmapped, and they show
up as :code:`nobody`::

  $ ls -n /tmp/foo
  -rw-rw---- 1 902 902 0 Sep 28 15:40 /tmp/foo
  $ ls -l /tmp/foo
  -rw-rw---- 1 sig sig 0 Sep 28 15:40 /tmp/foo
  $ ch-run /var/tmp/hello.sqfs -- bash
  > ls -n /tmp/foo
  -rw-rw---- 1 65534 65534 843 Sep 28 21:40 /tmp/foo
  > ls -l /tmp/foo
  -rw-rw---- 1 nobody nogroup 843 Sep 28 21:40 /tmp/foo

User namespaces have a similar mapping for GIDs, with the same limitation ---
exactly one arbitrary container GID maps to your effective *primary* GID. This
can lead to some strange-looking results, because only one of your GIDs can be
mapped in any given container. All the rest become :code:`nogroup`::

  $ id
  uid=901(charlie) gid=901(charlie) groups=901(charlie),903(nerds),904(losers)
  $ ch-run /var/tmp/hello.sqfs -- id
  uid=901(charlie) gid=901(charlie) groups=901(charlie),65534(nogroup)
  $ ch-run --gid 903 /var/tmp/hello.sqfs -- id
  uid=901(charlie) gid=903(nerds) groups=903(nerds),65534(nogroup)

However, this doesn’t affect access. The container process retains the same
GIDs from the host perspective, and as always, the host IDs are what control
access::

  $ ls -l /tmp/primary /tmp/supplemental
  -rw-rw---- 1 sig charlie 0 Sep 28 15:47 /tmp/primary
  -rw-rw---- 1 sig nerds  0 Sep 28 15:48 /tmp/supplemental
  $ ch-run /var/tmp/hello.sqfs -- bash
  > cat /tmp/primary > /dev/null
  > cat /tmp/supplemental > /dev/null

One area where functionality *is* reduced is that :code:`chgrp(1)` becomes
useless. Using an unmapped group or :code:`nogroup` fails, and using a mapped
group is a no-op because it’s mapped back to the host GID::

  $ ls -l /tmp/bar
  rw-rw---- 1 charlie charlie 0 Sep 28 16:12 /tmp/bar
  $ ch-run /var/tmp/hello.sqfs -- chgrp nerds /tmp/bar
  chgrp: changing group of '/tmp/bar': Invalid argument
  $ ch-run /var/tmp/hello.sqfs -- chgrp nogroup /tmp/bar
  chgrp: changing group of '/tmp/bar': Invalid argument
  $ ch-run --gid 903 /var/tmp/hello.sqfs -- chgrp nerds /tmp/bar
  $ ls -l /tmp/bar
  -rw-rw---- 1 charlie charlie 0 Sep 28 16:12 /tmp/bar

Workarounds include :code:`chgrp(1)` on the host or fastidious use of setgid
directories::

  $ mkdir /tmp/baz
  $ chgrp nerds /tmp/baz
  $ chmod 2770 /tmp/baz
  $ ls -ld /tmp/baz
  drwxrws--- 2 charlie nerds 40 Sep 28 16:19 /tmp/baz
  $ ch-run /var/tmp/hello.sqfs -- touch /tmp/baz/foo
  $ ls -l /tmp/baz/foo
  -rw-rw---- 1 charlie nerds 0 Sep 28 16:21 /tmp/baz/foo

Apache Spark
------------

This example is in :code:`examples/spark`. Build a SquashFS and upload it to
your supercomputer.

Interactive
~~~~~~~~~~~

We need to first create a basic configuration for Spark, as the defaults in
the Dockerfile are insufficient. For real jobs, you’ll want to also configure
performance parameters such as memory use; see `the documentation
<http://spark.apache.org/docs/latest/configuration.html>`_. First::

  $ mkdir -p ~/sparkconf
  $ chmod 700 ~/sparkconf

We’ll want to use the supercomputer’s high-speed network. For this example,
we’ll find the Spark master’s IP manually::

  $ ip -o -f inet addr show | cut -d/ -f1
  1: lo    inet 127.0.0.1
  2: eth0  inet 192.168.8.3
  8: eth1  inet 10.8.8.3

Your site support can tell you which to use. In this case, we'll use 10.8.8.3.

Create some configuration files. Replace :code:`[MYSECRET]` with a string only
you know. Edit to match your system; in particular, use local disks instead of
:code:`/tmp` if you have them::

  $ cat > ~/sparkconf/spark-env.sh
  SPARK_LOCAL_DIRS=/tmp/spark
  SPARK_LOG_DIR=/tmp/spark/log
  SPARK_WORKER_DIR=/tmp/spark
  SPARK_LOCAL_IP=127.0.0.1
  SPARK_MASTER_HOST=10.8.8.3
  $ cat > ~/sparkconf/spark-defaults.conf
  spark.authenticate true
  spark.authenticate.secret [MYSECRET]

We can now start the Spark master::

  $ ch-run -b ~/sparkconf /var/tmp/spark.sqfs -- /spark/sbin/start-master.sh

Look at the log in :code:`/tmp/spark/log` to see that the master started
correctly::

  $ tail -7 /tmp/spark/log/*master*.out
  17/02/24 22:37:21 INFO Master: Starting Spark master at spark://10.8.8.3:7077
  17/02/24 22:37:21 INFO Master: Running Spark version 2.0.2
  17/02/24 22:37:22 INFO Utils: Successfully started service 'MasterUI' on port 8080.
  17/02/24 22:37:22 INFO MasterWebUI: Bound MasterWebUI to 127.0.0.1, and started at http://127.0.0.1:8080
  17/02/24 22:37:22 INFO Utils: Successfully started service on port 6066.
  17/02/24 22:37:22 INFO StandaloneRestServer: Started REST server for submitting applications on port 6066
  17/02/24 22:37:22 INFO Master: I have been elected leader! New state: ALIVE

If you can run a web browser on the node, browse to
:code:`http://localhost:8080` for the Spark master web interface. Because this
capability varies, the tutorial does not depend on it, but it can be
informative. Refresh after each key step below.

The Spark workers need to know how to reach the master. This is via a URL; you
can get it from the log excerpt above, or consult the web interface. For
example::

  $ MASTER_URL=spark://10.8.8.3:7077

Next, start one worker on each compute node.

In this tutorial, we start the workers using :code:`srun` in a way that
prevents any subsequent :code:`srun` invocations from running until the Spark
workers exit. For our purposes here, that’s OK, but it’s a significant
limitation for some jobs. (See `issue #230
<https://github.com/hpc/charliecloud/issues/230>`_.) Alternatives include
:code:`pdsh`, which is the approach we use for the Spark tests
(:code:`examples/other/spark/test.bats`), or a simple for loop of :code:`ssh`
calls. Both of these are also quite clunky and do not scale well.

::

  $ srun sh -c "   ch-run -b ~/sparkconf /var/tmp/spark.sqfs -- \
                          spark/sbin/start-slave.sh $MASTER_URL \
                && sleep infinity" &

One of the advantages of Spark is that it’s resilient: if a worker becomes
unavailable, the computation simply proceeds without it. However, this can
mask issues as well. For example, this example will run perfectly fine with
just one worker, or all four workers on the same node, which aren’t what we
want.

Check the master log to see that the right number of workers registered::

  $  fgrep worker /tmp/spark/log/*master*.out
  17/02/24 22:52:24 INFO Master: Registering worker 127.0.0.1:39890 with 16 cores, 187.8 GB RAM
  17/02/24 22:52:24 INFO Master: Registering worker 127.0.0.1:44735 with 16 cores, 187.8 GB RAM
  17/02/24 22:52:24 INFO Master: Registering worker 127.0.0.1:22445 with 16 cores, 187.8 GB RAM
  17/02/24 22:52:24 INFO Master: Registering worker 127.0.0.1:29473 with 16 cores, 187.8 GB RAM

Despite the workers calling themselves 127.0.0.1, they really are running
across the allocation. (The confusion happens because of our
:code:`$SPARK_LOCAL_IP` setting above.) This can be verified by examining logs
on each compute node. For example (note single quotes)::

  $ ssh 10.8.8.4 -- tail -3 '/tmp/spark/log/*worker*.out'
  17/02/24 22:52:24 INFO Worker: Connecting to master 10.8.8.3:7077...
  17/02/24 22:52:24 INFO TransportClientFactory: Successfully created connection to /10.8.8.3:7077 after 263 ms (216 ms spent in bootstraps)
  17/02/24 22:52:24 INFO Worker: Successfully registered with master spark://10.8.8.3:7077

We can now start an interactive shell to do some Spark computing::

  $ ch-run -b ~/sparkconf /var/tmp/spark.sqfs -- /spark/bin/pyspark --master $MASTER_URL

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

  $ ch-run -b ~/sparkconf /var/tmp/spark.sqfs -- \
           /spark/bin/spark-submit --master $MASTER_URL \
           /spark/examples/src/main/python/pi.py 1024
  [...]
  Pi is roughly 3.141211
  [...]

Exit your allocation. Slurm will clean up the Spark daemons.

Success! Next, we’ll run a similar job non-interactively.

Non-interactive
~~~~~~~~~~~~~~~

We’ll re-use much of the above to run the same computation non-interactively.
For brevity, the Slurm script at :code:`examples/other/spark/slurm.sh` is not
reproduced here.

Submit it as follows. It requires three arguments: the squashball, the image
directory to unpack into, and the high-speed network interface. Again, consult
your site administrators for the latter.

::

  $ sbatch -N4 slurm.sh spark.sqfs /var/tmp ib0
  Submitted batch job 86754

Output::

  $ fgrep 'Pi is' slurm-86754.out
  Pi is roughly 3.141393

Success! (to four significant digits)

..  LocalWords:  NEWROOT rhel oldfind oldf mem drwxr xr sig drwxrws mpihello
..  LocalWords:  openmpi rwxr rwxrwx cn cpus sparkconf MasterWebUI MasterUI
..  LocalWords:  StandaloneRestServer MYSECRET TransportClientFactory sc tf
..  LocalWords:  containery lockdev subsys cryptsetup utmp xf bca Recv df af
..  LocalWords:  minirootfs alpinelinux cdrom ffdafff cb alluneed
..  LocalWords:  pL ib
