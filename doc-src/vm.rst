.. _virtualbox_build:

Pre-installed virtual machine
*****************************

This page explains how to create and use a single-node virtual machine with
Charliecloud and Docker pre-installed. This lets you:

  * use Charliecloud on Macs and Windows
  * quickly try out Charliecloud without installing anything

You can use this CentOS 7 VM either with `Vagrant
<https://www.vagrantup.com>`_ or with `VirtualBox
<https://www.virtualbox.org/>`_ alone. Various settings are specified, but in
most cases we have not done any particular tuning, so use your judgement, and
feedback is welcome.

.. contents::
   :depth: 2
   :local:

.. warning::

   These instructions provide for an SSH server in the virtual machine guest
   that is accessible to anyone logged into the host. It is your
   responsibility to ensure this is safe and compliant with your
   organization's policies, or modify the procedure accordingly.


Import and use an :code:`ova` appliance file with plain VirtualBox
===================================================================

This procedure imports a :code:`.ova` file (created using the instructions
below) into VirtualBox and walks you through logging in and running a brief
Hello World in Charliecloud. You will act as user :code:`charlie`, who has
passwordless :code:`sudo`.

The Charliecloud developers do not distribute a :code:`.ova` file. You will
need to get it from your site, a third party, or build it yourself with
Vagrant using the instructions below.

Prerequisite: Installed and working VirtualBox. (You do not need Vagrant.)

Configure VirtualBox
--------------------

1. Set *Preferences* → *Proxy* if needed at your site.

Import the appliance
--------------------

1. Download the :code:`charliecloud_centos7.ova` file (or whatever your site
   has called it).
2. *File* → *Import appliance*. Choose :code:`charliecloud_centos7.ova` and click *Continue*.
3. Review the settings.

   * CPU should match the number of cores in your system.
   * RAM should be reasonable. Anywhere from 2GiB to half your system RAM will
     probably work.
   * Check *Reinitialize the MAC address of all network cards*.

4. Click *Import*.
5. Verify that the appliance's port forwarding is acceptable to you and your
   site: *Details* → *Network* → *Adapter 1* → *Advanced* → *Port
   Forwarding*.

Log in and try Charliecloud
---------------------------

1. Start the VM by clicking the green arrow.

2. Wait for it to boot.

3. Click on the console window, where user :code:`charlie` is logged in. (If
   the VM "captures" your mouse pointer, type the key combination listed in
   the lower-right corner of the window to release it.)

4. Change your password. (You must use :code:`sudo` because you have
   passwordless :code:`sudo` but don't know your password.)

::

   $ sudo passwd charlie

5. SSH (from terminal on the host) into the VM using the password you just set.
   (Accessing the VM using SSH rather than the console is generally more
   pleasant, because you have a nice terminal with native copy-and-paste, etc.)

::

  $ ssh -p 2222 charlie@localhost

6. Build and run a container:

::

  $ ch-build -t hello -f /usr/local/src/charliecloud/examples/serial/hello \
             /usr/local/src/charliecloud
  $ ch-builder2tar hello /var/tmp
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
  * Configure :code:`/var/tmp` to be a :code:`tmpfs`, if you have enough RAM,
    for better performance.

Build and use the VM with Vagrant
=================================

This procedure builds and provisions an idiomatic Vagrant virtual machine. You
should also read the Vagrantfile in :code:`packaging/vagrant` before
proceeding. This contains the specific details on build and provisioning,
which are not repeated here.

Prerequisite: You already know how to use Vagrant.

Caveats and gotchas
-------------------

In no particular order:

* While Vagrant supports a wide variety of host and virtual machine providers,
  this procedure is tested only on VirtualBox on a Mac. Current Vagrant
  versions should work, but we don't track specifically which ones. (Anyone
  who wants to help us broaden this support, please get in touch.)

* Switching between proxy and no-proxy environments is not currently
  supported. If you have a mixed environment (e.g. laptops that travel between
  a corporate network and the wild), you may want to provide two separate
  images.

* Provisioning is not idempotent. Running the provisioners again will have
  undefined results.

* The documentation is not built. Use the web documentation instead of man
  pages.

Install Vagrant and plugins
---------------------------

You can install VirtualBox and Vagrant either manually using website downloads
or with Homebrew::

  $ brew cask install virtualbox virtualbox-extension-pack vagrant

Sanity check::

  $ vagrant version
  Installed Version: 2.1.2
  Latest Version: 2.1.2

  You're running an up-to-date version of Vagrant!

Then, install the needed plugins::

  $ vagrant plugin install vagrant-disksize \
                           vagrant-proxyconf \
                           vagrant-reload \
                           vagrant-vbguest

Build and provision
-------------------

To build the VM and install Docker, Charliecloud, etc.::

  $ cd packaging/vagrant
  $ CH_VERSION=v0.9.1 vagrant up

This takes less than 5 minutes.

If you want the head of the master branch, omit :code:`CH_VERSION`.

Then, optionally run the Charliecloud tests::

  $ vagrant provision --provision-with=test

This runs the full Charliecloud test suite, which takes quite a while (maybe
1–2 hours). Go have lunch, and then second lunch, and then third lunch.

Note that the test output does not have a TTY, so you will not have the tidy
checkmarks. The last test printed is the last one that completed, not the one
currently running.

If the tests don't pass, that's a bug. Please report it!

Now you can :code:`vagrant ssh` and do all the usual Vagrant stuff.


Build :code:`.ova` appliance file with Vagrant and VirtualBox
=============================================================

This section uses Vagrant and the VirtualBox GUI to create a :code:`.ova` file
that you can provide to end users as described above. You should read the
above section on using the VM with Vagrant as well.

Remove old virtual machine
--------------------------

.. warning::

   If you are using a Vagrant virtual machine for your own use, make sure
   you're not removing it here, unless you are sure it's disposable.

Each time we create a new image to distribute, we start from scratch rather
than updating the old image. Therefore, we must remove the old image.

1. Destroy the old virtual machine::

     $ cd packaging/vagrant
     $ vagrant destroy

2. Remove deleted disk images from the VirtualBox media manager: *File* →
   *Virtual Media Manager*. Right click on and remove any :code:`.vmdk` with a
   red exclamation icon next to them.

Build and provision
-------------------

The most important differences with this build procedure have to do with
login. A second user :code:`charlie` is created and endowed with passwordless
:code:`sudo`; SSH will allow login with password; and the console will
automatically log in :code:`charlie`. You need to reboot for the latter to
take effect (which is done in the next step).

::

   $ CH_VERSION=v0.9.1 vagrant up
   $ vagrant provision --provision-with=ova

Snapshot for distribution
-------------------------

We want to distribute a small appliance file, but one that passes the tests.
Running the tests greatly bloats the appliance. Therefore, we'll take a
snapshot of the powered-off VM named :code:`exportme`, run the tests, and then
roll back to the snapshot before exporting.

::

   $ vagrant halt
   $ VBoxManage modifyvm charliebox --defaultfrontend default
   $ vagrant snapshot save exportme

.. note::

   If you wish to use the appliance yourself, and you prefer to use plain
   VirtualBox instead of Vagrant, now is a good time to clone the VM and use
   the clone. This will protect your VM from Vagrant's attentions later.

Test Charliecloud
-----------------

Restart and test::

   $ vagrant up --provision-with=test

You might also show the console in the VirtualBox GUI and make sure
:code:`charlie` is logged in.

Export appliance :code:`.ova` file
----------------------------------

This creates a :code:`.ova` file, which is a standard way to package a virtual
machine image with metadata. Some else can then import it into their own
VirtualBox, as described above. (In principle, other virtual machine emulators
should work as well, but we haven't tried.)

These steps are done in the VirtualBox GUI because I haven't figured
out a way to produce a :code:`.ova` in Vagrant, only Vagrant "boxes".

#. Shut down the VM (you can just power it off).

#. Restore the snapshot *exportme*. (Don't use :code:`vagrant shapshot
   restore` because it boots the snapshot and runs the provisioners again.)

#. *File* → *Export appliance*.

#. Select your VM, *charliebox*. Click *Continue*.

#. Configure the export:

   * *Format*: OVF 2.0. (Note: Changing this menu resets the filename.)
   * *File*: Directory and filename you want. (The install procedure above
     uses :code:`charliecloud_centos7.ova`.)
   * *Write manifest file*: unchecked

#. Click *Continue*.

#. Check the descriptive information and click *Export*. (For example, maybe
   you want to put the Charliecloud version in the *Version* field.)

#. Distribute the resulting file, which should be about 800–900MiB.
