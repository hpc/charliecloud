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

5. SSH (from terminal on the host) into the VM using the password you just set.
   (Accessing the VM using SSH rather than the console is generally more
   pleasant, because you have a nice terminal with native copy-and-paste, etc.)

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

.. _virtualbox_build:



Build with Vagrant
==================

This procuedure will build and configure a VirtualBox guest machine 
automatically using `Vagrant <https://www.vagrantup.com/docs/index.html>`_.
Vagrant is a command line utility tool for building and
managing virtual machine environments in a single workflow.

Your Charliecloud-VirtualBox machine configuration will be as follows:

- **Name** — Charliecloud-VirtualBox
- **CPUs** — Automatic (equal to host)
- **Memory** — ~4 GB
- **Disk** — 40 GB 
- **Additional Storage** — 80 GB stored at ~/VirtualBox VMs/ch-storage/ch-disk.vdi and mounted at :code:`/var/tmp/ch`
- **Operating System** — Centos 7
- **Proxy** — Your proxy environment variables will be automatically configured based on the value of your host's :code:`$http_proxy` environment variable
- **Software** — Charliecloud (upstream), OpenMPI 2.1.3, and Docker

Install Vagrant
---------------

1. `Download Vagrant <https://www.vagrantup.com/downloads.html>`_

2. Install Vagrant on your operating system. Confirm installation
with :code:`vagrant version`:

::

    $ vagrant verrion
    Installed Version: 2.1.2
    Latest Version: 2.1.2
    
    You're running an up-to-date version of Vagrant

3. We will now install three plugins: one to handle proxy environment variables,
another to allow us to restart the VM without user intervention, and one to add 
persistent disk storage to `~/VirtualBox VMs/ch-storage/` (for full scope
testing).

::

    $ vagrant plugin install vagrant-proxyconf 
    $ vagrant plugin install vagrant-reload
    $ vagrant plugin install vagrant-persistent-storage

Build your guest machine
------------------------

The Charliecloud-VirtualBox VM Vagrantfile consists of a few provisions, some of which
are optional. Each provision is responsible for installing a package or configuring 
aspects of the guest environment. The provisions are as follows:

- **bootstrap** — responsible for core packages, namespace configuration, and persistent storage mount permissions
- **groups** — adds the chtest group and enables the vagrant user to run sudo commands without a password
- **dockerproxy** — adds the proxy environment variables to Docker's systemd service proxy-conf file
- **openmpi (optional)** — installs OpenMPI 2.1.3
- **chmake** — install charliecloud (upstream) into `/home/vagrant/charliecloud`)
- **chtests** — runs the full scope of charliecloud tests

1. Step inside your `charliecloud/vagrant` directory:

::

    $ cd ~/charliecloud/vagrant


2. Initiate the virtual machine build sequence. This will take several minutes.:

::

    $ vagrant up


3. Install charliecloud

::

    $ vagrant up --provision-with chmake


4. Install OpenMPI (optional)

::

    $ vagrant up --provision-with openmpi

5. Run test suite (Optional)

::

    $ vagrant up --provision-with chtests

.. warning::

    Running the test suite through vagrant provisioning can error
    when building docker images. This behavior does not happen when running
    the test suite manually (within the VM) and is encouraged if you enouncter
    errors.

Your VirtualBox guest machine is now built and running. From here, you
can ssh (from host terminal) into your machine.

Use your guest machine
------------------------

SSH in and try Charliecloud
~~~~~~~~~~~~~~~~~~~~~~~~~~~

1. From within your :code:`~/charliecloud/vagrant` directory, SSH into the guest:

::

    $ vagrant ssh

You are now ready to make all of your wildest Charliecloud dreams come
true.

Possible next steps:

  * Follow the :doc:`tutorial <tutorial>`.
  * Run the :ref:`test suite <install_test-charliecloud>` in
    :code:`/usr/share/doc/charliecloud/test`.

.. note::

    You may now :code:`suspend`, :code:`halt`, or save
    a :code:`snapshot` of your guest machine at your leisure.

Shutting down your virtual machine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Vagrant's :code:`halt` command will shutdown your running virtual machine.
Vagrant will first attempt to gracefully shutdown the machine by running
the guest OS shutdown mechanism. If this fails, Vagrant will just shut
down the machine.

To shutdown your machine, use the :code:`halt` command:

::

    $ vagrant halt

To relaunch your machine, use vagrant's :code:`up` command:

::

    $ vagrant up

Suspending your virtual machine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Vagrant's :code:`suspend` command effectively saves the exact point-in-time
state of the mahine so that when you :code:`resume` it later, it will
return running immediately from that point.

To suspend your machine, use the :code:`suspend` command:

::

    $ vagrant suspend

To resume running your machine, use the :code:`resume` command:

::

    $ vagrant resume

Snapshotting your virtual machine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Snapshots record a point-in-time state of a guest machine. You can
then quickly restore to this environment. This lets you experiment
and try things and quickly restore back to a previous state.

To snapshot your current state, use the :code:`snapshot save` command:

::

    $ vagrant snapshot save [vm-name] $NAME

To restore your snapshot, use the :code:`snapshot restore` command:

::

    $ vagrant snapshot restore [vm-name] $NAME

Destroying your guest machine
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This command stops the running machine Vagrant is managing and
destroys all resources that were created during the machine creation
process. After running this command, your computer should be left at
a clean state, as if you never created the guest machine in the first place.

To destroy your machine, use the*:code:`destroy` command:

::

    $ vagrant destroy
