VirtualBox appliance
********************

This page explains how to create and use a single-node `VirtualBox
<https://www.virtualbox.org/>`_ virtual machine appliance with Charliecloud and
Docker pre-installed. This lets you:

  * use Charliecloud on Macs and Windows
  * quickly try out Charliecloud without following the install procedure

The virtual machine uses CentOS 7 with an ElRepo LTS kernel. We use the
:code:`kernel.org` mirror for CentOS, but any should work. Various settings
are specified, but in most cases we have not done an particular tuning, so use
your judgement, and feedback is welcome. We assume Bash shell.

This procedure assumes you already have VirtualBox installed and working.

.. contents::
   :depth: 2
   :local:


Installing and using the appliance
==================================

FIXME (coming soon)


Building the appliance
======================


Initialize VM
-------------

Configure *Preferences* -> *Proxy* if needed.

Create a new VM in VirtualBox:

* Memory: 4 GiB
* Disk: 48 GiB, VDI dynamically allocated

Additional non-default settings:

* *System*

  * *Processor*

    * *Processor(s)*: 4

* *Network*

  * *Adapter 1*

    * *Advanced*

      * *Attached to*: NAT
      * *Adapter Type*: Paravirtualized Network
      * *Port Forwarding*: add the following rule (but see caveat above):

        * *Name*: ssh from localhost
        * *Protocol*: TCP
        * *Host IP*: 127.0.0.1
        * *Host Port*: 2022
        * *Guest IP*: 10.0.2.15
        * *Guest Port*: 22


Install CentOS
--------------

Download the `NetInstall ISO
<http://mirrors.kernel.org/centos/7/isos/x86_64/>`_ from your favorite mirror.
Attach it to the virtual optical drive of your VM by double-clicking on
*[Optical drive] Empty*.

Start the VM. Choose *Install CentOS Linux 7*.

Under *Installation summary*, configure (in this order):

* *Network & host name*
  * Enable *eth0*; verify it gets an IP and correct DNS.
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

* *Root password*: Set to something random (e.g. :code:`pwgen -cny 12`), which
  you can then forget because it will never be needed again.
* *User creation*:

  * *User name*: charlie
  * *Make this user administrator*: yes
  * *Password*: If the appliance will be used on single-user desktops, or
    other appropriate situations, and it does not conflict with your
    organization's policies, a null password such as "foobar" can be used.
    Otherwise, choose a good password.

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

We want :code:`sudo` to (1) accept :code:`charlie` without a password, (2)
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
  $ exit

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

This is not strictly necessary, but it will enable you to run MPI-based images
using the host MPI, as you would on a cluster. Match the MPI version in
:code:`examples/mpi/mpihello/Dockerfile`.

(CentOS has an OpenMPI RPM, but it's the wrong version and lacks an
:code:`mpirun` command.)

::

  $ cd /usr/local/src
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
  $ sudo chgrp wheel .
  $ sudo chmod 2775 .
  $ ls -ld .
  drwxrwsr-x. 2 root wheel 6 Nov  5  2016 .
  $ git clone --recursive https://www.github.com/hpc/charliecloud.git
  $ cd charliecloud
  $ make
  $ sudo make install PREFIX=/usr

Basic sanity::

  $ which ch-run
  /usr/bin/ch-run
  $ ch-run --version
  0.2.2~pre+00ffb9b

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

* FIXME (coming soon)
* Shut down.
* Revert to :code:`exportme`.
* Export :code:`.ova` should be about 4GB.


Upgrading the appliance
=======================

FIXME (coming soon)
