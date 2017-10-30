VirtualBox appliance
********************

This page explains how to create and use a single-node `VirtualBox
<https://www.virtualbox.org/>`_ virtual machine appliance with Charliecloud and
Docker pre-installed. This lets you:

  * use Charliecloud on Macs and Windows
  * quickly try out Charliecloud without following the install procedure

The virtual machine uses CentOS 7 with an ElRepo LTS kernel. We use the
:code:`kernel.org` mirror for CentOS, but any should work. Various settings
are specified, but in most cases we have not done any particular tuning, so
use your judgement, and feedback is welcome. We assume Bash shell.

This procedure assumes you already have VirtualBox installed and working.

.. contents::
   :depth: 2
   :local:


Install and use the appliance
=============================

This procedure imports a provided :code:`.ova` file into VirtualBox and walks
you through logging in and running a brief Hello World in Charliecloud. You
will act as user :code:`charlie`, who has passwordless :code:`sudo`.

.. warning::

   These instructions provide for an SSH server in the guest that is
   accessible to anyone logged into the host. It is your responsibility to
   ensure this is safe and compliant with your organization's policies, or
   modify the procedure accordingly.

Configure VirtualBox
--------------------

1. Set *Preferences* -> *Proxy* if needed at your site.

Install the appliance
---------------------

1. Download the :code:`charliecloud_centos7.ova` file (or whatever your site
   has called it).
2. *File* -> *Import appliance*. Choose :code:`charliecloud_centos7.ova` and click *Continue*.
3. Review the settings.

   * CPU should match the number of cores in your system.
   * RAM should be reasonable. Anywhere from 2GiB to half your system RAM will
     probably work.
   * Check *Reinitialize the MAC address of all network cards*.

4. Click *Import*.
5. Verify that the appliance's port forwarding is acceptable to you and your
   site: *Details* -> *Network* -> *Adapter 1* -> *Advanced* -> *Port
   Forwarding*.

Log in and try Charliecloud
---------------------------

1. Start the VM by clicking the green arrow.

2. Wait for it to boot.

3. Click on the console window, where user :code:`charlie` is logged in. (If
   the VM "captures" your mouse pointer, type the key combination listed in
   the lower-right corner of the window to release it.)

4. Change your password:

::

   $ sudo passwd charlie

5. SSH into the VM using the password you just set. (Accessing the VM using
   SSH rather than the console is generally more pleasant, because you have a
   nice terminal with native copy-and-paste, etc.)

::

  $ ssh -p 2022 charlie@localhost

6. Run a container:

::

  $ ch-docker2tar hello /var/tmp
  57M /var/tmp/hello.tar.gz
  $ ch-tar2dir /var/tmp/hello.tar.gz /var/tmp
  creating new image /var/tmp/hello
  /var/tmp/hello unpacked ok
  $ cat /etc/redhat-release
  CentOS Linux release 7.3.1611 (Core)
  $ ch-run /var/tmp/hello -- /bin/bash
  > cat /etc/debian_version
  8.9
  > exit

Congratulations! You've successfully used Charliecloud. Now all of your
wildest dreams will come true.

Shut down the VM at your leisure.

Possible next steps:

  * Follow the :doc:`tutorial <tutorial>`.
  * Run the :ref:`test suite <install_test-charliecloud>` in
    :code:`/usr/share/doc/charliecloud/test`. (Note that the environment
    variables are already configured for you in this appliance.)


Build the appliance
===================


Initialize VM
-------------

Configure *Preferences* -> *Proxy* if needed.

Create a new VM called *Charliecloud (CentOS 7)* in VirtualBox. We used the
following specifications:

* *Processors(s):* However many you have in the box you are using to build the
  appliance. This value will be adjusted by users when they install the
  appliance.

* *Memory:* 4 GiB. Less might work too. This can be adjusted as needed.

* *Disk:* 24 GiB, VDI dynamically allocated. We've run demos with 8 GiB, but
  that's not enough to run the Charliecloud test suite. The downside of being
  generous is more use of the host disk. The image file starts small and grows
  as needed, so unused space doesn't consume real resources. Note however that
  the image file does not shrink if you delete files in the guest (modulo
  heroics — image files can be compacted to remove zero pages, so you need to
  zero out the free space in the guest filesystem for this to work).

Additional non-default settings:

* *Network*

  * *Adapter 1*

    * *Advanced*

      * *Attached to:* NAT
      * *Adapter Type:* Paravirtualized Network
      * *Port Forwarding:* add the following rule (but see caveat above):

        * *Name:* ssh from localhost
        * *Protocol:* TCP
        * *Host IP:* 127.0.0.1
        * *Host Port:* 2022
        * *Guest IP:* 10.0.2.15
        * *Guest Port:* 22


Install CentOS
--------------

Download the `NetInstall ISO
<http://mirrors.kernel.org/centos/7/isos/x86_64/>`_ from your favorite mirror.
Attach it to the virtual optical drive of your VM by double-clicking on
*[Optical drive] Empty*.

Start the VM. Choose *Install CentOS Linux 7*.

Under *Installation summary*, configure (in this order):

* *Network & host name*

  * Enable *eth0*; verify it gets 10.0.2.15 and correct DNS.

* *Date & time*

  * Enable *Network Time*
  * Select your time zone

* *Installation source*

  * *On the network*: :code:`https://mirrors.kernel.org/centos/7/os/x86_64/`
  * *Proxy setup*: as appropriate for your network

* *Software selection*

  * *Base environment:* Minimal Install
  * *Add-Ons*: Development Tools

* *Installation destination*

  * No changes needed but the installer wants you to click in and look.

Click *Begin installation*. Configure:

* *Root password:* Something random (e.g. :code:`pwgen -cny 24`), which you
  can then forget because it will never be needed again. Users of the
  appliance will not have access to this password but will to its hash in
  :code:`/etc/shadow`.

* *User creation:*

  * *User name:* charlie
  * *Make this user administrator:* yes
  * *Password:* Decent password that meets your organization's requirements.
    Appliance user access is same as the root password.

Click *Finish configuration*, then *Reboot* and wait for the login prompt to
come up in the console. Note that the install ISO will be automatically
ejected.


Configure guest OS
------------------

Log in
~~~~~~

SSH into the guest. (This will give you a fully functional native terminal
with copy and paste, your preferred configuration, etc.)

::

  $ ssh -p 2022 charlie@localhost

Update sudoers
~~~~~~~~~~~~~~

We want :code:`sudo` to (1) accept :code:`charlie` without a password and (2)
have access to the proxy environment variables.

::

  $ sudo visudo

Comment out:

.. code-block:: none

  ## Allows people in group wheel to run all commands
  %wheel  ALL=(ALL)       ALL

Uncomment:

.. code-block:: none

  ## Same thing without a password
  # %wheel        ALL=(ALL)       NOPASSWD: ALL

Add:

.. code-block:: none

  Defaults    env_keep+="DISPLAY auto_proxy HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy"

Configure proxy
~~~~~~~~~~~~~~~

If your site uses a web proxy, you'll need to configure the VM to use it. The
setup described here also lets you turn on and off the proxy as needed with
the :code:`proxy-on` and :code:`proxy-off` shell functions.

Create a file :code:`/etc/profile.d/proxy.sh` containing, for example, the
following. Note that the only editor you have so far is :code:`vi`, and you'll
need to :code:`sudo`.

.. code-block:: sh

  proxy-on () {
    export HTTP_PROXY=http://proxy.example.com:8080
    export http_proxy=$HTTP_PROXY
    export HTTPS_PROXY=$HTTP_PROXY
    export https_proxy=$HTTP_PROXY
    export ALL_PROXY=$HTTP_PROXY
    export all_proxy=$HTTP_PROXY
    export NO_PROXY='localhost,127.0.0.1,.example.com'
    export no_proxy=$NO_PROXY
  }

  proxy-off () {
    unset -v HTTP_PROXY http_proxy
    unset -v HTTPS_PROXY https_proxy
    unset -v ALL_PROXY all_proxy
    unset -v NO_PROXY no_proxy
  }

  proxy-on

Test::

  $ exec bash
  $ set | fgrep -i proxy
  ALL_PROXY=http://proxy.example.com:8080
  [...]
  $ sudo bash
  # set | fgrep -i proxy
  ALL_PROXY=http://proxy.example.com:8080
  [...]
  # exit

Install a decent user environment
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use :code:`yum` to install a basic environment suitable for your site. For
example::

  $ sudo yum upgrade
  $ sudo yum install emacs vim wget

.. note::

   CentOS includes Git 1.8 by default, which is quite old. It's sufficient for
   installing Charliecloud, but if you expect users to do any real development
   with Git, you probably want to install a newer version, perhaps from
   source.

Configure auto-login on console
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This sets the first virtual console to log in :code:`charlie` automatically
(i.e., without password). This increases user convenience and, combined with
passwordless :code:`sudo` above, it lets users set their own password for
:code:`charlie` without you needing to distribute the password set above. Even
on multi-user systems, this is secure because the VM console window is
displayed only in the invoking user's windowing environment.

Adapted from this `forum post
<https://www.centos.org/forums/viewtopic.php?t=48288>`_.

::

  $ cd /etc/systemd/system/getty.target.wants
  $ sudo cp /lib/systemd/system/getty\@.service getty\@tty1.service

Edit :code:`getty@tty1.service` to modify the :code:`ExecStart` line and add a
new line at the end, as follows:

.. code-block:: ini

  [Service]
  ;...
  ExecStart=-/sbin/agetty --autologin charlie --noclear %I
  ;...
  [Install]
  ;...
  ;Alias=getty@tty1.service

Reboot. The VM text console should be logged into :code:`charlie` with no user
interaction.

Upgrade kernel
~~~~~~~~~~~~~~

CentOS 7 comes with kernel version 3.10 (plus lots of Red Hat patches). In
order to run Charliecloud well, we need something newer. This can be obtained
from `ElRepo <http://elrepo.org>`_.

First, set the new kernel flavor to be the default on boot. Edit
:code:`/etc/sysconfig/kernel` and change :code:`DEFAULTKERNEL` from
:code:`kernel` to :code:`kernel-lt`.

Next, install the kernel::

  $ sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
  $ sudo rpm -Uvh https://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
  $ sudo yum upgrade
  $ sudo rpm --erase --nodeps kernel-headers
  $ sudo yum --enablerepo=elrepo-kernel install kernel-lt kernel-lt-headers kernel-lt-devel
  $ sudo yum check dependencies

Reboot. Log back in and verify that you're in the right kernel::

  $ uname -r
  4.4.85-1.el7.elrepo.x86_64

Install Guest Additions
~~~~~~~~~~~~~~~~~~~~~~~

The VirtualBox `Guest Additions
<https://www.virtualbox.org/manual/ch04.html>`_ add various tweaks to the
guest to make it work better with the host.

#. Raise the VM's console window.
#. From the menu bar, choose *Devices* -> *Insert Guest Additions CD Image*.

Install. It is OK if you get a complaint about skipping X.

::

  $ sudo mount /dev/cdrom /mnt
  $ sudo sh /mnt/VBoxLinuxAdditions.run
  $ sudo eject

Reboot.

Install OpenMPI
~~~~~~~~~~~~~~~

This will enable you to run MPI-based images using the host MPI, as you would
on a cluster. Match the MPI version in
:code:`examples/mpi/mpihello/Dockerfile`.

(CentOS has an OpenMPI RPM, but it's the wrong version and lacks an
:code:`mpirun` command.)

::

  $ cd /usr/local/src
  $ sudo chgrp wheel .
  $ sudo chmod 2775 .
  $ ls -ld .
  drwxrwsr-x. 2 root wheel 6 Nov  5  2016 .
  $ wget https://www.open-mpi.org/software/ompi/v1.10/downloads/openmpi-1.10.5.tar.gz
  $ tar xf openmpi-1.10.5.tar.gz
  $ rm openmpi-1.10.5.tar.gz
  $ cd openmpi-1.10.5/
  $ ./configure --prefix=/usr --disable-mpi-cxx --disable-mpi-fortran
  $ make -j$(getconf _NPROCESSORS_ONLN)
  $ sudo make install
  $ make clean
  $ ldconfig

Sanity::

  $ which mpirun
  $ mpirun --version
  mpirun (Open MPI) 1.10.5


Install Docker
--------------

See also Docker's `CentOS install documentation
<https://docs.docker.com/engine/installation/linux/centos/>`_.

Install
~~~~~~~

This will offer Docker's GPG key. Verify its fingerprint.

::

  $ sudo yum install yum-utils
  $ sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  $ sudo yum install docker-ce
  $ sudo systemctl enable docker
  $ sudo systemctl is-enabled docker
  enabled

Configure proxy
~~~~~~~~~~~~~~~

If needed at your site, create a file
:code:`/etc/systemd/system/docker.service.d/http-proxy.conf` with the
following content:

.. code-block:: ini

  [Service]
  Environment="HTTP_PROXY=http://proxy.example.com:8080"
  Environment="HTTPS_PROXY=http://proxy.example.com:8080"

Restart Docker and verify::

  $ sudo systemctl daemon-reload
  $ sudo systemctl restart docker
  $ systemctl show --property=Environment docker
  Environment=HTTP_PROXY=[...] HTTPS_PROXY=[...]

Note that there's nothing special to turn off the proxy if you are off-site;
you'll need to edit the file again.

Test
~~~~

Test that Docker is installed and working by running the Hello World image::

  $ sudo docker run hello-world
  [...]
  Hello from Docker!
  This message shows that your installation appears to be working correctly.


Install Charliecloud
--------------------

Set environment variables
~~~~~~~~~~~~~~~~~~~~~~~~~

Charliecloud's :code:`make test` needs some environment variables. Set these
by default for convenience.

Create a file :code:`/etc/profile.d/charliecloud.sh` with the following
content:

.. code-block:: sh

  export CH_TEST_TARDIR=/var/tmp/tarballs
  export CH_TEST_IMGDIR=/var/tmp/images
  export CH_TEST_PERMDIRS=skip

Test::

  $ exec bash
  $ set | fgrep CH_TEST
  CH_TEST_IMGDIR=/var/tmp/images
  CH_TEST_PERMDIRS=skip
  CH_TEST_TARDIR=/var/tmp/tarballs

Enable a second :code:`getty`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Charliecloud requires a :code:`getty` process for its test suite. CentOS runs
only a single :code:`getty` by default, so if you log in on the console,
Charliecloud will not pass its tests. Thus, enable a second one::

  $ sudo ln -s /usr/lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@tty2.service
  $ sudo systemctl start getty@tty2.service

Test::

  $ ps ax | egrep [g]etty
   751 tty1     Ss+    0:00 /sbin/agetty --noclear tty1 linux
  2885 tty2     Ss+    0:00 /sbin/agetty --noclear tty2 linux

Build and install Charliecloud
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This fetches the tip of :code:`master` in Charliecloud's GitHub repository. If
you want a different version, use Git commands to check it out.

::

  $ cd /usr/local/src
  $ git clone --recursive https://www.github.com/hpc/charliecloud.git
  $ cd charliecloud
  $ make
  $ sudo make install PREFIX=/usr

Basic sanity::

  $ which ch-run
  /usr/bin/ch-run
  $ ch-run --version
  0.2.2~pre+00ffb9b

.. _virtualbox_prime-docker-cache:

Prime Docker cache
~~~~~~~~~~~~~~~~~~

Running :code:`make test-build` will build all the necessary Docker layers.
This will speed things up if the user later wishes to make use of them.

Note that this step can take 20–30 minutes to do all the builds.

::

  $ cd /usr/share/doc/charliecloud/test
  $ make test-build
   ✓ create tarball directory if needed
   - documentations build (skipped: sphinx is not installed)
   ✓ executables seem sane
   ✓ proxy variables
  [...]
  41 tests, 0 failures, 1 skipped

But the tarballs will be overwritten by later runs, so remove them to reduce
VM image size for export. We'll zero them out first so that the export sees
the blocks as unused. (It does not understand filesystems, so it thinks
deleted but non-zero blocks are still in use.)

::

  $ cd /var/tmp/tarballs
  $ for i in *.tar.gz; do echo $i; shred -n0 --zero $i; done
  $ rm *.tar.gz


Create export snapshot
----------------------

Charliecloud's :code:`make test-run` and :code:`test-test` produce voluminous
image files that need not be in the appliance, in contrast with the primed
Docker cache as discussed above. However, we also don't want to export an
appliance that hasn't been tested. The solution is to make a snapshot of what
we do want to export, run the tests, and then return to the pre-test snapshot
and export it.

#. Shut down the VM.
#. Create a snapshot called *exportme*.
#. Boot the VM again and log in.


Finish testing Charliecloud
---------------------------

This runs the Charliecloud test suite in full. If it passes, then the snapshot
you created in the previous step is good to go.

::

  $ cd /usr/share/doc/charliecloud/test
  $ make test-all

Export appliance
----------------

This creates a :code:`.ova` file, which is a standard way to package a virtual
machine image with metadata. Someone else can then import it into their own
VirtualBox, as described above. In principle other virtual machine emulators
should work as well, though we haven't tried.

1. Shut down the VM.
2. Revert to snapshot *exportme*.
3. *File* -> *Export appliance*
4. Select your VM. Click *Continue*.
5. Configure the export:

   * *File:* Directory and filename you want. (The install procedure above
     uses :code:`charliecloud_centos7.ova`.)
   * *Format:* OVF 2.0
   * *Write Manifest file:* unchecked

6. Click *Continue*.
7. Check the decriptive information and click *Export*.
8. Distribute the resulting file (which should be about 5GiB).


Upgrade the appliance
=====================

Shut down the VM and roll back to *exportme*.

OS packages via :code:`yum`
---------------------------

::

  $ sudo yum upgrade
  $ sudo yum --enablerepo=elrepo-kernel install kernel-lt kernel-lt-headers kernel-lt-devel

You may also want to remove old, unneeded kernel packages::

  $ rpm -qa 'kernel*' | sort
  kernel-3.10.0-514.26.2.el7.x86_64
  kernel-3.10.0-514.el7.x86_64
  kernel-3.10.0-693.2.2.el7.x86_64
  kernel-devel-3.10.0-514.26.2.el7.x86_64
  kernel-devel-3.10.0-514.el7.x86_64
  kernel-devel-3.10.0-693.2.2.el7.x86_64
  kernel-lt-4.4.85-1.el7.elrepo.x86_64
  kernel-lt-devel-4.4.85-1.el7.elrepo.x86_64
  kernel-lt-headers-4.4.85-1.el7.elrepo.x86_64
  kernel-tools-3.10.0-693.2.2.el7.x86_64
  kernel-tools-libs-3.10.0-693.2.2.el7.x86_64
  $ sudo rpm --erase kernel-3.10.0-514.26.2.el7 [... etc ...]

Charliecloud
------------

::

  $ cd /usr/local/src/charliecloud
  $ git pull
  $ make clean
  $ make
  $ sudo make install PREFIX=/usr
  $ git log -n1
  commit 4ebff0a0d7352b69e4cf8b9f529b6247c17dbe86
  [...]
  $ which ch-run
  /usr/bin/ch-run
  $ ch-run --version
  0.2.2~pre+4ebff0a

Make sure the Git hashes match.

Docker images
-------------

Delete existing containers and images::

  $ sudo docker rm $(sudo docker ps -aq)
  $ sudo docker rmi -f $(sudo docker images -q)

Now, go to :ref:`virtualbox_prime-docker-cache` above and proceed.
