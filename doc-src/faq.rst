Frequently asked questions (FAQ)
********************************

.. contents::
   :depth: 2
   :local:


Error and warning messages
==========================

9p: Could not find request transport: virtio
--------------------------------------------

This happens when the right 9P modules are not loaded. In theory all the right
modules should be loaded automatically, but in practice they sometimes aren't.
You can fix this by `adding some modules to the initramfs
<http://superuser.com/a/536352/46580>`_.

9p: no channels available
-------------------------

Among other things, this error can mean that you're trying to mount a 9P
filesystem and there is no filesystem with the given tag. You might also get
:code:`mount: special device <FOO> does not exist` which is vaguely more
helpful.

:code:`mount -a` is likely to give this error multiple times, as standard
images have :code:`/etc/fstab` set up to mount several data directories which
might not exist. In this case, the error can be ignored.

job script hard link failed, copying instead
--------------------------------------------

Charliecloud tries to use a hard link for the job script, to make it possible
to edit the job script from the host side. If this fails, Charliecloud will
proceed with a copy instead. Everything will run fine, but edits on the host
side will not propagate into the guest, and edits in the guest will affect
only the copy in the job directory, not the original.

Symlinks cannot be used because the guest is not able to follow them beyond
the passed-through metadata directory.

The typical fix is to move the job script onto the same host filesystem as the
Charliecloud job directory.

mount: unknown filesystem type '9p'
-----------------------------------

Fileystem passthrough requires 9P filesystem support in the guest kernel. You
can check this with something like::

  > fgrep CONFIG_9P_FS /boot/config-3.16.0-30-generic
  CONFIG_9P_FS=m

You might instead see::

  # CONFIG_9P_FS is not set

In this case, you must find or compile a different kernel with
:code:`CONFIG_9P_FS` built in or as a module.

One route is to simply choose a different distribution. RHEL and derivatives
(e.g., CentOS) are known to have this problem; Debian is known to work. Fedora
is probably another good choice, though untested.

O_DIRECT unsupported
--------------------

Charliecloud tries to turn off the host file cache for virtual block devices
(e.g., root filesystem and temporary storage). This is not supported on some
filesystems. If this fails, Charliecloud will proceed with the host cache
turned on, which can have performance impact due to poor interaction between
the host and guest file caches.

serial8250: too much work for irq4
----------------------------------

This error occurs because KVM's emulated serial ports can happily digest data
at very high rates, which `confuses the kernel
<http://linux-kernel.2935.n7.nabble.com/PATCH-serial-remove-quot-too-much-work-for-irq-quot-printk-td229840.html>`_
because it expects serial ports to work at the advertised slower speed. There
is no real issue, and the error can safely be ignored.

Turning up the serial console to higher speeds did not make the errors go
away.

vde_switch: Could not remove ctl dir
------------------------------------

:code:`slirpvde` puts additional cruft in the VDE control directory and
doesn't remove it on exit. Then :code:`vde_switch` complains. Don't worry
about it.

vlan 0 is not connected to host network
---------------------------------------

This may mean that QEMU wasn't compiled with VDE support, which is necessary
for networking in workstation mode.


Something doesn't work
======================

I can't ping the outside world, but it's reachable by other network stuff
-------------------------------------------------------------------------

User mode and VDE networking does not carry ICMP beyond the virtual cluster.
Only TCP and UDP work.

Intermittent connectivity problems between guests
-------------------------------------------------

This happens sometimes in workstation mode. The problem, I believe, is that
VDE is simply buggy. Try again (i.e., invoke the problem command again --- no
need to reboot the cluster) and it will very likely work.

As SSH is the underlying transport for many things, such as MPI, this can
manifest in a variety of ways.

Testing failed because orted is listening to some port
------------------------------------------------------

:code:`orted` is an OpenMPI daemon. I believe that in Charliecloud
configurations, it listens only briefly during bootup. That is, the failure is
a race condition.

This failure can be ignored.

VGA console won't relinquish mouse grab
---------------------------------------

There are few possibilities:

#. The default grab key chord is :code:`Control_L-Alt_L`; that is, the ones on
   the left side of the keyboard. The ones on the right won't work.

#. Your keyboard may be sending :code:`Meta_L` instead of :code:`Alt_L`, which
   works in many applications, but not QEMU. Under XQuartz on OS X, you can
   get :code:`Alt_L` from the left Option key if *Option keys send Alt_L and
   Alt_R* is checked in the preferences.

#. You have changed the grab keys from the default with QEMU arguments
   :code:`-alt-grab` or :code:`ctrl-grab`.

VGA console does not show the whole screen
------------------------------------------

Sometimes, the VGA window is smaller than the screen resolution. Try a
different card type (:code:`oneguest --vgatype`), or just scroll around using
the old-school X11 viewport scrolling.

Resizing the VGA window will not help, as this just scales the window rather
than changing the underlying emulated resolution. However, if you want an
amusingly squashed display, this is a good bet.


Configuration
=============

How can I tell if I'm using the faster virtio drivers?
------------------------------------------------------

In your guest, try::

  > dmesg | fgrep virtio
  [    0.745660] virtio-pci 0000:00:02.0: irq 41 for MSI/MSI-X
  [    0.745675] virtio-pci 0000:00:02.0: irq 42 for MSI/MSI-X
  [    0.745687] virtio-pci 0000:00:02.0: irq 43 for MSI/MSI-X
  [...]
  >  fgrep -i virtio /boot/config-$(uname -r)
  CONFIG_VIRTIO_BLK=m
  CONFIG_VIRTIO_NET=m
  CONFIG_VIRTIO=m
  [...]

If your output is significantly different, you might not be using
:code:`virtio`. See `link 1 <http://wiki.mikejung.biz/KVM_/_Xen#virtio-blk>`_
and `link 2 <http://serverfault.com/questions/478726/>`_.

How can I persist the root filesystem without :code:`vcluster --commit`?
------------------------------------------------------------------------

In some cases, you may not realize you want to persist root filesystem changes
until the cluster is up (i.e., you did not specify :code:`--commit` but then
change your mind). This is no problem --- install what you need and then shut
down the cluster.

This FAQ entry show how to do manually what :code:`vcluster` does
automatically. As an example, start up a new headless cluster and wait for it
to shut down:

.. code-block:: bash

  $ vcluster -n1
             --job ~/charliecloud/examples/null.sh
             --jobdir charlie
             image.qcow2

Now, we can examine the images that are left::

  $ ls charlie/run
  0.overlay.qcow2  vde
  $ qemu-img info charlie/run/0.overlay.qcow2
  image: charlie/run/0.overlay.qcow2
  file format: qcow2
  virtual size: 16G (17179869184 bytes)
  disk size: 17M
  cluster_size: 524288
  backing file: /data/vm/image.qcow2
  Format specific information:
      compat: 1.1
      lazy refcounts: false

The key :code:`backing file` tells us that this is an overlay image based on
the noted file. That is, it contains only the blocks which have been changed
with respect to :code:`image.qcow2`. The commit process simply
saves these changes into the backing file. For example::

  $ qemu-img commit charlie/run/0.overlay.qcow2
  Image committed.

Now root filesystem changes made by guest 0 are saved in the main VM image.

.. note::

   Overlay images are tied to the parent image by absolute path. This path can
   be adjusted; try :code:`man qemu-img`. Make sure you know what you are
   doing before moving things around.
