Image configuration
*******************

The following checklist is a good starting point for creating a virtual
machine image. Note that this is not recommended for typical users; almost
always, modifying a provided base image is less work.

Detailed instructions are not provided; instead, the list contains pointers to
the Debian Jessie reference image.

.. contents::
   :depth: 2
   :local:

.. note::

   Unfortunately, the reference image is not provided with Charliecloud itself
   at this time. We are working to rectify this deficiency.


Booting an installer overview
=============================

::

    $ newimage centos-6.5_base.qcow2
    $ oneguest --monitor --vga --boot centos-6.5-x86_64-DVD1.iso centos-6.5_base.qcow2
    $ oneguest --monitor --vga -d /tmp centos-6.5_base.qcow2

.. note::

   `Monitor voodoo <http://www.linux-kvm.org/page/Change_cdrom>`_ is required
   to insert or change CD/DVD media. If you don't need to do this, you can
   omit :code:`--monitor`.


During install
==============


* Set the label :code:`root` on the root filesystem, if you can.

* Name the initial user, which will be the primary job user, :code:`charlie`.

* No swap space (our scripts deal with this later).


After install
=============

Console and friends
-------------------

* Attach the console to both the display and the first serial port. See the
  `kernel documentation
  <https://www.kernel.org/doc/Documentation/serial-console.txt>`_ and edit
  :code:`/etc/default/grub` appropriately, then run :code:`update-grub`.

  You may also wish to turn off :code:`FANCYTTY`, which can clutter the
  console log with ANSI escape sequences. Do so in
  :code:`/etc/lsb-base-logging.sh`, though there seem to be still a few overly
  enthusiastic ANSI escapers.

* Set up the console to stay on the ROM font (the traditional DOS look).
  Optional, but I prefer the aesthetics. Edit
  :code:`/etc/default/console-setup` and :code:`/etc/default/grub`.

Filesystem
----------

* Set up environment variables for interactive shells (e.g.
  :code:`/etc/profile.d/charlie_proxy.sh`). Note that this only sets advisory
  environment variables in certain contexts, so it doesn't work for all apps.
  This includes:

  * HTTP/HTTPS proxy. (Not needed for :code:`apt` to work.)
  * Charliecloud environment variables. (See issue #35.)

* Make :code:`/ch` and subdirectories.

* Install the init script :code:`/etc/rc.local`.

* Set up :code:`/etc/fstab` to mount the filesystems. Don't forget
  :code:`nofail` on things that might not be present at boot time.

Network
-------

* Disable persistent network device naming. This causes trouble because MAC
  addresses change between boots. If the network does not work, this is a
  likely culprit, especially if it does work on guest 0 but not other guests.

  * Debian Wheezy: Create an empty
    :code:`/etc/udev/rules.d/75-persistent-net-generator.rules` and delete
    :code:`/etc/udev/rules.d/70-persistent-net.rules` (see
    :code:`/usr/share/doc/udev/README.Debian.gz`).

  * Linux distributions with the new `"Predictable Network Interface Names"
    <http://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/>`_:
    **FIXME**

* Configure networking:

  * :code:`/etc/network/interfaces`
  * :code:`/etc/hosts` symlinked to :code:`/ch/meta/hosts`
  * :code:`/etc/resolv.conf` symlinked to :code:`/ch/meta/resolv.conf`

Users and groups
----------------

* Change default umask to 002 in :code:`/etc/login.defs`. Also update
  :code:`/etc/pam.d/common-session` because of a `Debian bug
  <https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=646692>`_. (See
  :doc:`fs-passthrough` for why.)

* Change the primary job user :code:`charlie`\ 's UID to 65530 and
  user-private group :code:`charlie`\ 's GID to 65530. Update all files owned
  by him in the virtual system::

    > usermod -u 65530 charlie
    > groupmod -g 65530 charlie
    > usermod -g 65530 charlie    # maybe?
    > find / -xdev -group 1000 -exec chgrp -vh 65530 {} \;

* Make serial ports R/W for job user. On Debian-derived systems, simply add
  the user to the :code:`dialout` group.

* Set up passwords & authentication:

  * Configure SSH:

    * allow keys (:code:`PubkeyAuthentication yes`); this is the default
    * forbid passwords (:code:`PasswordAuthentication no`)
    * forbid root login (:code:`PermitRootLogin no`)

  * Set root's password to something strong.
  * Edit :code:`/etc/sudoers`:

    * Add :code:`charlie` (e.g., by adding him to group :code:`sudo`)
    * Set :code:`NOPASSWD` on the relevant line(s)
    * Pass through the HTTP proxy variables

  * Set :code:`charlie` to have no password (:code:`passwd -d`).

  The basic philosophy is: once inside, access control is minimal; access
  controls via the console are minimal; SSH is reasonably locked down.

* Set up SSH keys for :code:`charlie`. The pair is passwordless, to permit
  unattended login from other members of the virtual cluster, so use with
  care.

  * :code:`ssh-keygen`; enter an empty password.
  * Copy :code:`id_rsa.pub` to :code:`authorized_keys`.
  * Edit :code:`authorized_keys` to restrict the key to virtual cluster IPs.
  * Edit :code:`config` to not check host keys within the virtual cluster.

Misc
----

* Remove unnecessary servers, for example mail (:code:`exim4` on Debian), NTP,
  NFS, RPC, etc.

* Configure MPI (e.g., files in :code:`/etc/openmpi`).

Notes on :code:`systemd`-based distros
======================================

Here are some quick, unhelpful notes on setup for :code:`systemd`-based
distributions (e.g., Debian Jessie).

* :code:`/ch/tmp` needs :code:`noauto`, not :code:`nofail`, in :code:`fstab`.

* :code:`journald.conf` to send output to console only (:code:`Storage=none`
  and :code:`ForwardToSyslog=yes`?)

* :code:`systemd.conf` :code:`ShowStatus=no` to remove fancy boot messages and
  their ANSI codes from the serial console.

* :code:`/etc/systemd/system/charliecloud.service`

* Set :code:`umask 0007` in :code:`.bashrc`. :code:`login.defs` setting is not
  applied consistently (only interactive logins?).
