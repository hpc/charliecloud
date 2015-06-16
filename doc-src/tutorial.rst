Tutorial
********

This tutorial will teach you to start a Charliecloud virtual cluster,
understand how it fits together, run a sample job in interactive and batch
mode, and install your own software. It will work in both workstation and
cluster mode as long as the Charliecloud :code:`bin` directory is on your
:code:`$PATH`.

You will need a Charliecloud-enabled virtual machine image; obtain one from
your local operators. This tutorial assumes the image is called
:code:`image.qcow2` and is running Debian Wheezy. Other distributions will
have minor differences.

.. contents::
   :depth: 2
   :local:

.. note::

   Charliecloud VM images are simply filesystem images; they contain no
   metadata about type of machine, etc. Think of it as a hard disk rather than
   a whole computer. This simple approach contrasts with Amazon EC2 and other
   cloud providers, where the metaphor is a complete machine.


Your first virtual cluster
==========================

In this section, we will run a virtual cluster and poke around a little bit.
You will want at least three terminals open.

Getting help
------------

The Charliecloud script you'll use the most (if you use the others at all) is
called :code:`vcluster`. All the Charliecloud scripts have decent help, so
let's see what :code:`vcluster` has to say about itself::

  $ vcluster --help

Starting the virtual network
----------------------------

A Charliecloud cluster depends on the kernel bridge and TAP devices to talk to
itself, and kernel NAT to talk to the outside world. A script is included to
set this up; configuration is required, e.g.::

  $ sudo mkdir -p /etc/charliecloud
  $ sudo sh -c 'cat > /etc/charliecloud/config.sh'
  TAP_OWNER=reidpr   # you
  FWD_IFACE=em1      # network interface to be used for NAT
  ^D
  $ sudo ~/charliecloud/misc/network-w-linux start
  $ sudo ~/charliecloud/misc/network-w-linux status
  [...]

The script is a standard SysV init script and so can be configured to start at
boot time. Root access is required. If you don't have this, talk to your
system administrator.

.. warning::

   Any program on the host can connect to the Charliecloud guests; also, any
   program running as you can connect to the TAP devices and use the
   Charliecloud NAT to connect to the outside world. Be sure you understand
   the implications of this before starting the virtual network or a virtual
   cluster.


Starting a virtual cluster
--------------------------

Now, we'll start up a smallish virtual cluster. If you are in workstation
mode, you will need to explicitly say what resource levels you want; if you
are in cluster mode, Charliecloud will figure out reasonable defaults
automatically (one VM per physical compute node).

For the purposes of this tutorial, we will assume that you've stored the VM
image in :code:`/data/vm`::

  $ cd /data/vm
  $ vcluster -n4 --xterm image.qcow2

Let's review that command line briefly. We are asking for:

* A virtual cluster of 4 nodes.
* Each VM console in a separate xterm.
* Boot the root filesystem in :code:`image.cow2`.

Run the command and wait until the cluster boots. :code:`vcluster` will print
information about its environment and progress of component launch. Four
:code:`xterm` will appear, and you can watch boot progress of the VMs
themselves there. Eventually, you will see a console login prompt in each
:code:`xterm`.

Logging in
----------

Log into :code:`chgu0` (guest 0) as :code:`charlie`; there is no password.
Once you're in, try::

  > whoami
  charlie
  > sudo whoami
  root

This reflects the basic access philosophy of Charliecloud images:

#. Getting in is controlled.
#. Once you're in, you're in.

In this case, we assume that being able to make the console available is
sufficient authentication (because one must have read access to the root
filesystem image), and so we do not require additional authentication to log
in.

In the case of SSH, we set up keys, which is covered below.

Similarly, by default, no password is required for :code:`charlie` to
:code:`sudo`.

Filesystems
-----------

Let us examine the filesystems mounted by a Charliecloud guest::

  > df -Th
  Filesystem     Type      Size  Used Avail Use% Mounted on
  /dev/vda1      ext4       16G  2.3G   13G  15% /
  udev           devtmpfs   10M     0   10M   0% /dev
  tmpfs          tmpfs     403M  352K  402M   1% /run
  tmpfs          tmpfs    1006M     0 1006M   0% /dev/shm
  tmpfs          tmpfs     5.0M     0  5.0M   0% /run/lock
  tmpfs          tmpfs    1006M     0 1006M   0% /sys/fs/cgroup
  meta           9p        911G  189G  676G  22% /ch/meta
  opt            9p        911G  189G  676G  22% /ch/opt
  /dev/vdb2      ext4      2.0G  3.0M  2.0G   1% /ch/tmp
  tmpfs          tmpfs     202M     0  202M   0% /run/user/1001

In addition to standard temporary filesystems found on modern Linux (the six
:code:`tmpfs` and :code:`devtmpfs` filesystems), there are four mounted
filesystems. Let us discuss them in turn.

Root filesystem
~~~~~~~~~~~~~~~

Device :code:`/dev/vda1` is an ext4 filesystem mounted at the root. This
corresponds to two files in the host filesystem: a read-only virtual disk
*base image* — the :code:`image.qcow2` that you specified to :code:`vcluster`
— and an *overlay* which contains all the changes made to the disk. (We will
see this overlay file in the next section.) This gives two desirable
properties:

* Each virtual machine has an independent, read-write view of the root
  filesystem, which starts identically for each VM.

* These changes can be either discarded or committed after the VM exists.
  Charliecloud provides direct support for committing guest 0, but you can use
  :code:`qemu-img` directly to commit any one of the guests. We will use this
  facility later in the tutorial for installing software.

:code:`/ch/tmp`
~~~~~~~~~~~~~~~

:code:`/dev/vdb2` is another virtual disk image used for temporary data not
needed after the VM exits. Each VM has an independent :code:`/ch/tmp`.
:code:`vcluster` creates a new image for each VM during startup, and the
Charliecloud boot scripts create a filesystem on it.

::

  > ls /ch/tmp
  lost+found

The size and location on the host of the disk image can be adjusted with
:code:`vcluster` switches.

(:code:`/dev/vdb1` is used for swap.)

:code:`/ch/meta`
~~~~~~~~~~~~~~~~

Here we encounter our first instance of *filesystem passthrough*. This is a
directory on the host which is passed through to all VMs. It contains
information about the virtual cluster itself::

  > ls /ch/meta
  guest-count  guests    hosts          proxy.sh     sync  using-vde
  guest-macs   hostfile  host-userdata  resolv.conf  test

We will not explore its contents in detail in this tutorial (see the :doc:`API
documentation <api>`). However, one example::

  > ls -l /etc/hosts
  lrwxrwxrwx 1 root root 14 Aug 19 12:28 /etc/hosts -> /ch/meta/hosts

That is, :code:`/etc/hosts` in Charliecloud guests is constructed on-demand by
:code:`vcluster` each time a new cluster is booted.

.. tip::

   The filesystem type :code:`9p` may be one that you have not seen before.
   Filesystem passthrough is accomplished by a user-space agent in QEMU which
   carries out file operations on behalf of the guest. Communication with this
   agent is over the `Plan 9 network filesystem protocol
   <http://en.wikipedia.org/wiki/9P>`_.

   If you try :code:`ls -l`, you may notice some quirks about this mount.
   These will be explained later in this tutorial.

:code:`/ch/opt`
~~~~~~~~~~~~~~~

This passthrough directory contains scripts and other information used by
Charliecloud guests. Recall that we are running Debian 8.0, "Jessie"::

  > ls /ch/opt
  jessie linux  wheezy
  > ls /ch/opt/jessie
  10-storage.sh  30-hostname.sh  99-runjob.sh  charlie.sh  util.sh
  20-users.py    80-sync.sh      boot.sh       network.sh

For example, the script :code:`boot.sh` coordinates various tasks for booting
a Charliecloud guest; it is invoked by :code:`rc.local` or a :code:`systemd`
service. This lets us improve booting without needing to update each
individual VM image.

Contents of the job directory
-----------------------------

We now return to the host to explore the host's view of a running Charliecloud
virtual cluster.

:code:`vcluster` creates a *job directory* to support the cluster. By default,
this is named :code:`charlie` with a timestamp suffix, but you can change this
if you prefer. Open a second terminal and :code:`cd` into the job directory
for the currently-running cluster::

  $ cd /data/vm/charlie.19690720_141804
  $ ls
  meta  out  run

We see that there are three directories here.

:code:`meta`
~~~~~~~~~~~~

:code:`meta` is the same directory as :code:`/ch/meta` on all the guests::

  $ ls meta
  guest-count  guests    hosts          proxy.sh     sync  using-vde
  guest-macs   hostfile  host-userdata  resolv.conf  test

:code:`run`
~~~~~~~~~~~

This directory contains runtime data for the cluster::

  $ ls run
  0.overlay.qcow2  1.overlay.qcow2  2.overlay.qcow2  3.overlay.qcow2  vde
  0.tmp.qcow2      1.tmp.qcow2      2.tmp.qcow2      3.tmp.qcow2

Here we find:

#. An overlay root disk image for each VM.
#. The temporary disk image for each VM.
#. A directory for the VDE2 virtual network to coordinate.

:code:`out`
~~~~~~~~~~~

Finally, this contains output from each of the guests::

  $ ls out
  0_console.out  1_console.out  2_console.out  3_console.out  slirpvde.out
  0_job.err      1_job.err      2_job.err      3_job.err      vde_switch.out
  0_job.out      1_job.out      2_job.out      3_job.out

Here we find:

1. Console output from each guest. Note that this is somewhat more
   comprehensive than what you see in the :code:`xterm` boot console, and it
   includes output from the Charliecloud boot scripts.

2. Standard output and error for the job script on each guest. These are only
   populated in batch (non-interactive) mode; empty files appear otherwise.

3. Output from the VDE virtual network programs.

These are implemented by redirecting virtual serial ports to files.

Guest console output is exceedingly useful in diagnosing problems. For
example::

  $ tail -F out/*_console.out out/slirpvde.out out/vde_switch.out

We use :code:`-F` as opposed to :code:`-f`, because it will follow the same
filename if the file is re-created, which happens when you boot a cluster
multiple times over the same job directory. This is a handy technique to avoid
a proliferation of soon-to-be-discarded job directories.

In this case, we are following the entire cluster, but often following just
guest 0 will be sufficient. Leave this running as we continue to explore our
cluster.

.. admonition:: Hey! What about :code:`opt`!?

   Indeed, we haven't yet explained where :code:`opt` is passed through from.
   It is the :code:`opt` directory in the Charliecloud source code.


Network topology
----------------

A virtual cluster is not much good if the nodes can't communicate. Therefore,
return to guest 0, and we will explore the cluster's network topology.

::

  > cat /etc/hosts
  127.0.0.1 localhost
  172.22.1.1 chgu0
  172.22.1.254 chgu0host
  172.22.1.2 chgu1
  172.22.1.254 chgu1host
  172.22.1.3 chgu2
  172.22.1.254 chgu2host
  172.22.1.4 chgu3
  172.22.1.254 chgu3host

Recall that :code:`/etc/hosts` is dynamically generated for each virtual
cluster. In this case, we have symbolic names and IP addresses for each of the
four nodes in our virtual cluster, as well as their hosts. Charliecloud uses
IP addresses in the private space 172.16.0.0/12; details can be found in the
:doc:`network topology section <networking>`.

Full TCP/IP service to other guests in the virtual cluster is provided. In
workstation mode, TCP/IP to the outside world is also provided via NAT.

Let's try some pinging. First, another guest in the cluster::

  > ping -c3 chgu1
  PING chgu1 (172.22.1.2) 56(84) bytes of data.
  64 bytes from chgu1 (172.22.1.2): icmp_req=1 ttl=64 time=20.0 ms
  64 bytes from chgu1 (172.22.1.2): icmp_req=2 ttl=64 time=0.545 ms
  64 bytes from chgu1 (172.22.1.2): icmp_req=3 ttl=64 time=0.550 ms

  --- chgu1 ping statistics ---
  3 packets transmitted, 3 received, 0% packet loss, time 2003ms
  rtt min/avg/max/mdev = 0.545/7.039/20.023/9.181 ms

Next, our host::

  > ping -c3 chgu0host
  PING chgu0host (172.22.1.254) 56(84) bytes of data.
  64 bytes from 172.22.1.254: icmp_req=1 ttl=255 time=0.808 ms
  64 bytes from 172.22.1.254: icmp_req=2 ttl=255 time=0.348 ms
  64 bytes from 172.22.1.254: icmp_req=3 ttl=255 time=0.349 ms

  --- 172.22.1.254 ping statistics ---
  3 packets transmitted, 3 received, 0% packet loss, time 2003ms
  rtt min/avg/max/mdev = 0.348/0.501/0.808/0.218 ms

Finally, the outside world (specifically, one of Google's public DNS
servers)::

  > ping -c3 -w5 8.8.8.8
  PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
  64 bytes from 8.8.8.8: icmp_seq=1 ttl=54 time=31.5 ms
  64 bytes from 8.8.8.8: icmp_seq=2 ttl=54 time=31.5 ms
  64 bytes from 8.8.8.8: icmp_seq=3 ttl=54 time=31.5 ms

  --- 8.8.8.8 ping statistics ---
  3 packets transmitted, 3 received, 0% packet loss, time 2003ms
  rtt min/avg/max/mdev = 31.555/31.571/31.584/0.205 ms

This works in workstation mode. In cluster mode, most configurations provide
no networking outside the virtual cluster, so this times out.

SSH
---

We can SSH from one guest into another without a password, because the
Charliecloud images have keys set up for this::

  > ssh chgu1 echo hello
  hello

We can also SSH into hosts, but this requires authentication::

  > ssh reidpr@chgu0host echo hello
  reidpr@chgu0host's password:
  hello

SSH access from the host to guests is also available. To authenticate, you
must add your SSH public key to :code:`~charlie/.ssh/authorized_keys`. One
method is as follows. First, copy your key to the clipboard::

  $ pbcopy < ~/.ssh/id_rsa.pub

Then, on the guest::

  > cat >> ~/.ssh/authorized_keys
  [paste the key]
  ^D
  > cat ~/.ssh/authorized_keys
  [...]
  ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC4ZfQ0yZgyIaQZLl1FA8nPD+1eZCzDsEf+vVqreqad
  9f+5LP5J/QOU8ZB9F0jqRAod7Y5zspUNFwP7/4n/59ny37bdxpBd0p+0qGUX4UmkCWlD900EfLw5gyJU
  icwI/O/TWFV70HiQX9Tol7Z+WD5k9JR42MjHcQP+hf6Jsk1th8KjqZg+NGcmAiC84pXmFYOnFE38L/nd
  66iTLVhSEYLvXnU5DIx4ZZvRXbDN65C1Gq7unMebjJD7XtuV07znjUpq4ZMtuhAT7mcSdDB9zdg4HO2g
  XE0lCR92uv15h4f3KMygEj4ehFKI9Ii/N6vMyyEsUSpTZ6rz9Z7TuetsQJcf reidpr@example.com

.. tip::

   Make sure that the whole key went in, as certain configurations (e.g., OS
   X) have a low limit on the number of bytes that can be copied and pasted
   into an :code:`xterm` at once. You can also use the :code:`--curses`
   console instead, which we will encounter below.

   If you manually copy and paste the key, watch out for line breaks sneaking
   in.

You should now be able to log into the guests from the host. :code:`vcluster`
prints the IP address of guest 0 during startup, and other guests' IPs are
available in :code:`meta/hosts`. Log in as :code:`charlie`, not yourself. For
example::

  $ ssh charlie@172.22.1.1 hostname
  chgu0
  $ ssh charlie@172.22.1.3 hostname
  chgu2

Shut the cluster down
---------------------

When you are done with the cluster, shut down guest 0::

  > sudo shutdown -h now
  Broadcast message from root@chgu0 (tty1) (Mon Jul 21 11:54:30 1969):

  The system is going down for system halt NOW!
  [...]
  deleted ./charlie.19690720_141804/run/0.tmp.qcow2
  oneguest done

After shutdown is complete , close the :code:`xterm`. :code:`vcluster` will
clean up the other guests and then exit.


Your first virtual job
======================

Starting a cluster with less clutter
------------------------------------

Start a new virtual cluster as follows (all one line):

.. code-block:: bash

  $ vcluster -n3
             --curses
             --jobdir charlie
             --job ~/charliecloud/examples/mpihello/mpihello.sh
             --interactive
             --dir ~/charliecloud/examples/mpihello/data
             image.qcow2

This involves five new common options:

* :code:`--curses` shows the console for guest 0 in the current terminal,
  while remaining guests are headless. This reduces window clutter, and the
  console for guest 0 is must more commonly used than the others.

* :code:`--jobdir` gives the job directory a specific name (in this case,
  :code:`./charlie`), overwriting any existing job directory at that location.
  This is useful when iterating a cluster, as it places files at known paths
  and avoids dropping multiple job directories that will never be referred to
  again.

* :code:`--job` gives a script defining the computation you wish to
  accomplish.

* :code:`--interactive` says not to run that script on boot, but simply make
  it available inside the guests.

* :code:`--dir` explicitly invokes filesystem passthrough, making the given
  directory available inside guests. This option can be repeated up to four
  times.

Once the cluster comes up, log in to guest 0.

Users, groups, and permissions under filesystem passthrough
-----------------------------------------------------------

In this cluster, we map a specific directory on the host,
:code:`~/charliecloud/examples/mpihello/data`, to :code:`/ch/data1` inside the
guest. This is a shared directory appearing in the same place on all guests.
Additional :code:`--dir` options would map :code:`/ch/data2`, :code:`3`, and
:code:`4`.

One of the tricky aspects of filesystem passthrough is mapping users and
groups from host to guest, because the host and guest can have completely
different users and groups. Charliecloud hides much of this complexity, but
there are a few subtleties that remain. This section explains the pitfalls and
best practices to avoid them.

Start by examining the passed-through directory and our user account on the
host::

  $ ls -l ~/charliecloud/examples/mpihello/data
  -rw-rw---- 1 reidpr reidpr 1606 Apr 27 16:18 hello.c
  -rwxrwxr-x 1 reidpr reidpr  784 Aug 19  2014 hello.py
  $ id
  uid=1001(reidpr) gid=1001(reidpr) groups=1001(reidpr),132(kvm),1000(twitter)

Things to notice here:

* The two files are owned by user :code:`reidpr`, group :code:`reidpr`.

* The files are readable by the *group* :code:`reidpr`.

* :code:`reidpr` (UID 1001) is in three groups: :code:`reidpr` (GID 1001),
  :code:`kvm` (GID 132), and :code:`twitter` (GID 1000).

Now, examine the same directory in the guest::

  > ls -l /ch/data1
  -rw-rw---- 1 charlie reidpr 1606 Apr 27 16:18 hello.c
  -rwxrwxr-x 1 charlie reidpr  784 Aug 19  2014 hello.py
  > id charlie
  uid=1001(charlie) gid=65530(charlie) groups=65530(charlie),1000(twitter),1001(reidpr)

Things to notice:

* The two files still owned by group :code:`reidpr`, but now their user is
  :code:`charlie`.

* Permission bits and other metadata are the same as on the host.

* :code:`charlie` (UID 1001) is in groups :code:`charlie` (GID 65530),
  :code:`reidpr` (GID 1001), and :code:`twitter` (GID 1000).

The Charliecloud magic is that guest users and groups are synchronized with
the host on boot. :code:`charlie` is adjusted to match the user running
Charliecloud, with two exceptions: its username, so it can be predictably
referred to, and system groups. The consequence is that :code:`charlie` — the
login user and job user with the guest — can read, write, and execute what
everything that :code:`reidpr` can, because the guest and host agree.

Permissions on passed-through directories are enforced by both the host and
guest. For example, let's try something that we should not be able to do::

  > cd /ch/data1
  > touch a
  > ls -l a
  -rw-rw---- 1 charlie reidpr 0 Apr 29 11:28 a
  > chown root:root a
  chown: changing ownership of 'a': Operation not permitted
  > sudo chown root:root a
  chown: changing ownership of 'a': Operation not permitted

Here, the first :code:`chown` was rejected by the guest, and the second was
approved by the guest (because of :code:`sudo`) but rejected by the host.
However, it works on a within-guest filesystem, because in this case the
host's access control does not get involved::

  > cd /ch/tmp
  > touch a
  > ls -l a
  -rw-rw---- 1 charlie charlie 0 Apr 29 11:34 a
  > chown root:root a
  > chown: changing ownership of 'a': Operation not permitted
  > sudo chown root:root a
  > ls -l a
  -rw-rw---- 1 root root 0 Apr 29 11:34 a

That is, passthrough file actions are carried out by QEMU (and proxied into
the VM as a 9P network filesystem), which is running unprivileged as us.
Therefore, we are unable to do anything in the virtual machine that we could
not do by running a normal program on the host, regardless of how we alter the
guest or unprivileged QEMU.

For the gory detail on filesystem passthrough, including possible paths not
taken (pun intended), see the :doc:`full passthrough documentation
<fs-passthrough>`.

.. caution::

   Above, we mentioned there are some gotchas with this arrangement. They
   include:

   * The guest :code:`umask` governs files created within the guest, even on
     passthrough filesystems, because the relevant system calls are passed
     through unchanged, so make sure it is a value appropriate for you.
     :code:`0007` is common if you want to share work with your groups,
     :code:`0077` for private work.

   * :code:`charlie`'s UID will change when the guest is booted by a host user
     with a different UID, which can happen when images are used by different
     people or the image is transferred between different hosts.
     :code:`charlie`'s home directory will be fixed, which can take some time
     if it contains many files, and files elsewhere in the guest will not be
     fixed.

   * System groups from the host are not imported into the guest, so some
     types of group-granted access will be erroneously rejected by the guest.
     Typically this is sysadmin-type stuff and unlikely to be encountered in
     practice, but you can work around it with :code:`sudo` inside the guest.


Running :code:`mpihello` in interactive mode
--------------------------------------------

Notice that in the last section, we slipped in a parallel computation.
Charliecloud images come with MPI installed by default, since it is a common
parallel framework familiar to the Charliecloud audience, and this tutorial
uses it for that reason. However, you can install whatever you wish.

Recall the argument :code:`--job mpihello.sh` specified above when we started
the cluster. This makes the given file appear as :code:`/ch/meta/jobscript`
within the VMs:

::

  $ head ~/charliecloud/examples/mpihello/mpihello.sh
  ​#!/bin/bash

  ​# Demonstrate that MPI works in C and Python.
  ​#
  ​# Requires ./data as first --dir.

  if [ "$CH_GUEST_ID" != 0 ]; then
      echo 'not guest 0; waiting for work'
      exit 0
  fi

::

  > head /ch/meta/jobscript
  ​#!/bin/bash

  ​# Demonstrate that MPI works in C and Python.
  ​#
  ​# Requires ./data as first --dir.

  ​if [ "$CH_GUEST_ID" != 0 ]; then
  ​    echo 'not guest 0; waiting for work'
  ​    exit 0
  ​fi

Take a few minutes to examine this script.

In non-interactive mode (covered in the next section), all guests run the job
script on boot. In this case, guest 0 initiates everything, so the script
opens with a test for guest ID and exits if it is not 0.

Let's try running it::

  > /ch/meta/jobscript
  Are we running on all nodes?
  chgu0
  chgu0
  chgu1
  chgu2
  chgu1
  chgu2

  Can we do MPI in C?
  0: We have 6 processors
  0: Hello 1! Processor 1 reporting for duty
  0: Hello 2! Processor 2 reporting for duty
  0: Hello 3! Processor 3 reporting for duty
  0: Hello 4! Processor 4 reporting for duty
  0: Hello 5! Processor 5 reporting for duty

  Can we do MPI in Python?
  5 workers finished, result on rank 0 is:
  {1: set([0, 3, 5, 6, 7, 8, 9, 'rank 1 on chgu0']),
   2: set([0, 3, 5, 6, 7, 8, 9, 'rank 2 on chgu1']),
   3: set([0, 3, 5, 6, 7, 8, 9, 'rank 3 on chgu1']),
   4: set([0, 3, 5, 6, 7, 8, 9, 'rank 4 on chgu2']),
   5: set([0, 3, 5, 6, 7, 8, 9, 'rank 5 on chgu2'])}

It worked! Congratulations on running your first Charliecloud virtual job!

The job script is implemented as a hard link (when possible) on the host side,
so you can edit it on the host and immediately re-run in the guest. This is a
quick way to iterate your computation.

Let's try it. Suppose that you are very old school and lower-case letters make
you uncomfortable. Edit (on the host)
:code:`~/charliecloud/examples/mpihello/data/hello.c` and change the string
literals to upper-case. Then, on the guest::

  > /ch/meta/jobscript
  [...]
  Can we do MPI in C?
  0: WE HAVE 6 PROCESSORS
  0: HELLO 1! PROCESSOR 1 REPORTING FOR DUTY
  0: HELLO 2! PROCESSOR 2 REPORTING FOR DUTY
  0: HELLO 3! PROCESSOR 3 REPORTING FOR DUTY
  0: HELLO 4! PROCESSOR 4 REPORTING FOR DUTY
  0: HELLO 5! PROCESSOR 5 REPORTING FOR DUTY
  [...]

Much better! If you like, you can also change the Python implementation and
the job script itself.

We are done with this cluster, so shut it down.

.. note::

   This workflow reflects the basic philosophy of Charliecloud work: **install
   dependencies within the virtual machine, but define jobs outside it.**
   Among other benefits, this lets you take advantage of package management
   facilities provided by the OS (e.g., :code:`apt-get`) and programming
   languages (e.g., :code:`pip`) while retaining flexibility and convenience
   for your own computations. For example, you need not install editors and a
   carefully tailored interactive environment inside the VM, and changes to
   your computation do not require distributing new virtual machine images.


Running :code:`mpihello` in batch mode
--------------------------------------

While interactive mode is great for iterating your computation, production
jobs are typically run in non-interactive mode. This section will walk you
through doing do.

First, start a :code:`tail -F` on the console output, so we can watch the
computation happen::

  $ cd /data/vm
  $ tail -F charlie/out/0_console.out

Then, in another terminal, run :code:`vcluster` as follows:

.. code-block:: bash

  $ vcluster -n3
             --jobdir charlie
             --job ~/charliecloud/examples/mpihello/mpihello.sh
             --dir ~/charliecloud/examples/mpihello/data
             image.qcow2

Notice the two differences from the previous invocation:

* :code:`--curses` (as well as :code:`--xterm`) are missing. Thus, the cluster
  will run entirely headless.

* :code:`--interactive` is missing. This instructs the cluster to boot up, run
  the job, and then shut down. You can still log into the cluster while it's
  running the job, but being logged in will not prevent shutdown when the job
  completes.

This is the type of command you would include in a SLURM job script.

Returning to your :code:`tail` output of the guest 0 console, some key lines
are::

  2014-12-02T13:47:39: running 99-runjob.sh
  2014-12-02T13:47:39: will shut down after job
  2014-12-02T13:47:39: forking to run user job
  2014-12-02T13:47:39: 99-runjob.sh done in 0 seconds
  2014-12-02T13:47:39: boot.sh done in 8 seconds
  2014-12-02T13:47:43: user job complete; writing 0.jobdone
  2014-12-02T13:47:43: shutting down

Here you can see the :code:`99-runjob.sh` boot script starting (but not
waiting for) your job, the completion notice for your job, and a notice that
the cluster is shutting down.

Now, examine your job output::

  $ cat charlie/out/0_job.err
  $ cat charlie/out/0_job.out

  Are we running on all nodes?
  chgu0
  chgu0
  chgu1
  chgu2
  chgu2
  chgu1

  Can we do MPI in C?
  0: WE HAVE 6 PROCESSORS
  0: HELLO 1! PROCESSOR 1 REPORTING FOR DUTY
  0: HELLO 2! PROCESSOR 2 REPORTING FOR DUTY
  0: HELLO 3! PROCESSOR 3 REPORTING FOR DUTY
  0: HELLO 4! PROCESSOR 4 REPORTING FOR DUTY
  0: HELLO 5! PROCESSOR 5 REPORTING FOR DUTY

  Can we do MPI in Python?
  5 workers finished, result on rank 0 is:
  {1: set([0, 3, 5, 6, 7, 8, 9, 'rank 1 on chgu0']),
   2: set([0, 3, 5, 6, 7, 8, 9, 'rank 2 on chgu1']),
   3: set([0, 3, 5, 6, 7, 8, 9, 'rank 3 on chgu1']),
   4: set([0, 3, 5, 6, 7, 8, 9, 'rank 4 on chgu2']),
   5: set([0, 3, 5, 6, 7, 8, 9, 'rank 5 on chgu2'])}

In this case, there were no errors, which is good, and the job output is the
same as we saw earlier in interactive mode.

Of course, this is simply the standard output and standard error of your job.
Real jobs will typically create output files of some kind; these should be
saved into the user passthrough directories (:code:`/ch/data[1234]`).

.. tip::

   The environment variables :code:`$CH_DATA[1234]` are set when the
   corresponding passthrough directories are mounted.


Installing your own software
============================

Starting a VM with persistent root filesystem
---------------------------------------------

Recall that each guest in a Charliecloud virtual cluster gets an independent
read-write copy of the root filesystem, starting from an identical state. That
is, while you can muck with the filesystem to your heart's content, your
changes will not persist to the next cluster unless you take special measures.
This section describes those measures.

Boot a new virtual cluster:

.. code-block:: bash

   $ vcluster -n1
              --commit 0
              --curses
              --jobdir charlie
              image.qcow2

New in this invocation:

* We've asked for a single-node cluster.

* :code:`--commit 0` says to save the changes to the root filesystem of guest
  0 to the image (:code:`image.qcow2`).

* The absence of :code:`--job` implies :code:`--interactive`.

Recall that :code:`vcluster` abruptly kills the remaining guests when guest 0
exits, potentially leaving their root filesystems in an inconsistent state.
Usually this is not a problem even when persisting changes, as it's typically
guest 0 whose changes are saved. However, if you do want to save changes on a
non-0 node, shut it down manually to get a consistent filesystem.

.. tip::

   If you use :code:`--commit` and later change your mind:

   * If the virtual cluster is still running, kill the to-be-commited
     :code:`qemu` process. :code:`vcluster` will see this as an error and not
     commit the root filesystem image.

   * If the virtual cluster is already shut down, you are out of luck. Hope
     you kept a backup...

Installing software
-------------------

A key goal of Charliecloud is to make installing software to support your
application easy. Thus, we take advantage of operating system and
language-specific package managers.

For example, let's install the package :code:`sl`::

  > sudo apt-get install sl
  Reading package lists... Done
  Building dependency tree
  Reading state information... Done
  The following NEW packages will be installed:
    sl
  [...]
  Setting up sl (3.03-17) ...
  > man sl | fgrep -A2 DESCRIPTION
  DESCRIPTION
         sl Displays animations aimed to correct users who accidentally enter sl
         instead of ls.  SL stands for Steam Locomotive.
  > sl
  [...]

:code:`sl` has several pleasant options, so experiment.

While we didn't in this case, you can also pass in a job script, etc., and try
your application's tests to interactively ensure you get all its dependencies.

Shut down the cluster. Note the following lines in the :code:`vcluster` output::

  ​$ qemu-img commit ./charlie/run/0.overlay.qcow2
  Image committed.
  deleted ./charlie/run/0.overlay.qcow2

This is :code:`vcluster` saving your changes into
:code:`image.qcow2`. The overlay image is then deleted, as it is
now invalid.

.. important::

   Be sure you charge the time you spend playing with :code:`sl` to the
   correct account.


**This concludes the tutorial.** You are now qualified to run Charliecloud
virtual clusters in interactive and non-interactive mode, run jobs, and
install software within your virtual cluster. The remainder of this
documentation covers more advanced topics. Have fun!
