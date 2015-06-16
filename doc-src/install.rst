Installing Charliecloud
***********************

.. contents::
   :depth: 2
   :local:

.. note::

  Charliecloud supports Linux hosts. OS X and Windows hosts are not currently
  supported because filesystem passthrough support is missing. For the same
  reason, OS X and Windows guests are unsupported. We hope to fix this
  deficiency in the future (patches are welcome!).

Installing on Linux
===================

This file explains how to install Charliecloud and run a small virtual cluster
on your x86-64 Linux machine. You can run Charliecloud over X11, so this
machine need not be your desktop or laptop.

Charliecloud is designed to have a fairly small number of dependencies, but
unfortunately, the major ones (QEMU itself and VDE networking) require
building from source.

The below assumes you put tarballs in :code:`/usr/local/src` and wish to install
into :code:`/usr/local`.

These instructions use Bash syntax.


Miscellaneous supporting software
---------------------------------

You need:

* A reasonably recent version of Git.

* GNU Stow (optional but highly recommended, as QEMU wants to mess with
  permissions of shared directories).

* Python 2.7.

* Python packages :code:`Sphinx` and :code:`sphinx-rtd-theme` (only if you
  wish to build the documentation).

You also need the build dependencies of QEMU and VDE. At a high level, these
can be obtained by repeatedly attempting to build and installing what's
missing.

For Ubuntu Vivid::

  $ sudo apt-get build-dep qemu


Charliecloud itself
-------------------

We install Charliecloud early, even though it cannot run until the
prerequisites are met, in order to access included files needed for installing
those prerequisites.

This assumes you are putting Charliecloud in :code:`~/charliecloud`. You may
want to put :code:`~/charliecloud/bin` on your :code:`$PATH`.

Install as follows::

  $ cd ~
  $ git clone git@git.lanl.gov:reidpr/charliecloud.git
  $ cd charliecloud
  $ make doc                # optional
  $ bin/vcluster --version
  0.1.4


KVM hypervisor
--------------

Virtual machine performance is much better with the KVM hypervisor (as opposed
to software emulation), which is built into the stock Linux kernel. All
kernels and x86 CPUs which are even vaguely modern support KVM, so it is
simply a matter of enabling KVM if it isn't already.

.. note::

   While Charliecloud currently requires KVM, it would be a very small patch
   to make the KVM command line switches passed to QEMU optional (hint, hint).

CPU support
~~~~~~~~~~~

To test if your CPU supports hardware virtualization (and thus KVM)::

  $ egrep -c '(vmx|svm)' /proc/cpuinfo

:code:`0` means no, a positive integer means yes.

BIOS support
~~~~~~~~~~~~

Hardware virtualization may also need to be enabled in the BIOS. Detecting
this setting and changing is dependent on your OS and hardware; you are best
off consulting Google for details.

Modern Debian-derived distributions include a command :code:`kvm-ok` in the
package :code:`cpu-checker` which makes this easy. If you get something like
this, you're golden::

  $ kvm-ok
  INFO: /dev/kvm exists
  KVM acceleration can be used

If something like this, you need to tweak your BIOS::

  $ kvm-ok
  INFO: /dev/kvm does not exist
  HINT:   sudo modprobe kvm_intel
  INFO: Your CPU supports KVM extensions
  INFO: KVM (vmx) is disabled by your BIOS
  HINT: Enter your BIOS setup and enable Virtualization Technology (VT),
        and then hard poweroff/poweron your system
  KVM acceleration can NOT be used


:code:`/dev/kvm` permissions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You need read/write access to :code:`/dev/kvm`. There are at least two ways
this is accomplished. Which you get depends on your distribution.

The traditional way is to put all KVM users in group :code:`kvm` and make the
device group R/W for that user::

  $ ls -l /dev/kvm
  crw-rw---- 1 root kvm 10, 232 Nov  7 10:36 /dev/kvm

The newfangled :code:`systemd` way is to make the device owned
:code:`root:root` and dynamically add users to the file's ACL when they log in
to the console (that is, anyone sitting at the computer can use KVM). Note the
trailing plus on the permissions, which implies the presence of an ACL:

.. Note: The following example contains zero-width space characters (Unicode
   code point U+200B) at the beginning of the leading-hash output lines, to
   prevent the "console" lexer from inappropriately highlighting them as a
   prompt and commands.

::

  $ ls -l /dev/kvm
  crw-rw----+ 1 root root 10, 232 Nov  7 10:36 /dev/kvm
  $ getfacl /dev/kvm
  getfacl: Removing leading '/' from absolute path names
  ​# file: dev/kvm
  ​# owner: root
  ​# group: root
  user::rw-
  user:lightdm:rw-
  group::---
  mask::rw-
  other::---

In the above, users :code:`root` and :code:`lightdm` can use KVM.

This causes problems if you want to run Charliecloud over the network, since
you are not sitting at the console.

You can fix the ACL manually after every boot with :code:`setfacl`, or you can
add a :code:`udev` rule to also grant access to users in group :code:`kvm`.
This can be accomplished as follows (note that you must paste the file
content)::

  $ sudo sh -c 'cat > /etc/udev/rules.d/99-fix-kvm.rules'
  SUBSYSTEM=="misc", KERNEL=="kvm", GROUP="kvm"
  ^D
  $ sudo udevadm trigger --action=add --sysname-match=kvm
  $ ls -l /dev/kvm
  crw-rw----+ 1 root kvm 10, 232 Nov 24 13:57 /dev/kvm

.. warning::

   This leaves the ACLs in place, so you can use KVM *either* if you are in
   the :code:`kvm` group or sitting at the console.


QEMU
----

We build QEMU from source for two reasons. First, distribution versions tend
to be stale. Second, VDE networking support is often not compiled in (e.g.,
`in Ubuntu
<https://bugs.launchpad.net/ubuntu/+source/qemu-kvm/+bug/776650>`_).

Download QEMU from the `official site <http://wiki.qemu.org/Download>`_. You
probably want to choose the most recent stable version, which is 2.1.2 as of
this writing (November 1914).

Build and install as follows::

  $ tar xjf qemu-2.1.2.tar.bz2
  $ cd qemu-2.1.2
  $ ./configure --prefix=/usr/local/stow/qemu-2.1.2 \
                --target-list=i386-softmmu,x86_64-softmmu \
                --enable-kvm \
                --enable-uuid \
                --enable-virtfs
  $ make
  $ make install
  $ stow -d /usr/local/stow -S qemu-2.1.2
  $ qemu-system-x86_64 --version
  QEMU emulator version 2.1.2, Copyright (c) 2003-2008 Fabrice Bellard

Note that :code:`configure` will pick up available libraries automatically, so
some of the above is redundant. However, we list it to document what
Charliecloud needs. :code:`--target-list` is short simply to improve compile
speed; you can add more/all targets if you want to other guest architectures
(note that KVM is not available for most targets).


*Now, move on to the next section to learn how to run your first virtual
cluster.*

