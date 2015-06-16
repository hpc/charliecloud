Filesystem passthrough
**********************

QEMU offers a very nice feature of filesystem passthrough: selected
directories on the host can be mounted in the guest. Then, the unprivileged
QEMU process acts on behalf of the guest to perform the desired options.

This file contains a very detailed description of how filesystem passthrough
works in Charliecloud, along with reasoning for various choices. You probably
don't need to read it if you just want to use Charliecloud.

Communication between the guest and QEMU uses the `9P protocol
<https://www.kernel.org/doc/Documentation/filesystems/9p.txt>`_ over the
:code:`virtio` transport. There is an `overview paper
<http://www.landley.net/kdocs/ols/2010/ols2010-pages-109-120.pdf>`_ which
describes the process as it stood in 2010.

Importantly, because the QEMU process runs as the user who invoked it, even
privileged users within the guest have the same access to host files as the
unprivileged invoking host user does. That is, root access to filesystems
applies only to filesystems wholly within the guest (e.g., a virtual block
device with a filesystem on it) and can't leak out.

.. contents::
   :depth: 2
   :local:

Uncoordinated UIDs and GIDs
===========================

There is some black magic involved, however. Among other things, UIDs and GIDs
are not shared between host and guest, and the 9P driver does not re-map any
UIDs or GIDs. This leads to some strange behavior because both guest and host
are applying independent permissions checks. For example, a simple :code:`ls`
on the host::

  $ ls -n
  -rw-rw---- 1 1001 1001 10 May 16 14:06 bar
  -rw-rw---- 1    0    0 10 May 16 14:06 foo
  $ ls -l
  -rw-rw---- 1 reidpr reidpr 10 May 16 14:06 bar
  -rw-rw---- 1 root   root   10 May 16 14:06 foo

Guest, same directory::

  > ls -n
  -rw-rw---- 1 1001 1001 10 May 16 14:06 bar
  -rw-rw---- 1    0    0 10 May 16 14:06 foo
  > ls -l
  -rw-rw---- 1 1001 1001 10 May 16 14:06 bar
  -rw-rw---- 1 root root 10 May 16 14:06 foo

The listings are the same with :code:`-n` (i.e., :code:`--numeric-uid-gid`),
but they differ with the more typical :code:`-l`. The file :code:`foo` shows
up as expected in the guest, because :code:`root:root` has the same UID (0)
and GID (0) in both host and guest. However, :code:`bar` is different. This is
because the file is owned by :code:`reidpr:reidpr` (UID 1001, GID 1001) on the
host, but in the guest we are running as the job user :code:`charlie`, UID
65530, and there is no guest user with UID 1001. Linux therefore displays the
UID because no user can be found.

.. note::

   Further confusion can occur if there is in fact a guest user with UID 1001;
   in this case, the guest OS will think that user owns the files. We will not
   explore this scenario more deeply, though it's important to be aware of
   it.

Let's try to access those two files as unprivileged :code:`charlie` within
the guest::

  > whoami
  charlie
  > cat foo
  cat: foo: Permission denied
  > cat bar
  cat: bar: Permission denied

The first result is expected; the host user :code:`reidpr` cannot read this
file. However, the second is surprising: :code:`reidpr` can read this file.
The problem is that the guest kernel interprets the permissions, sees
that the file is only readable by UID=1001 or GID=1001, neither of which
apply to :code:`charlie`, and so it denies access.

We can try the same as guest root::

  > sudo cat foo
  cat: foo: Permission denied
  > sudo cat bar
  hello bar

In this case, it's :code:`cat foo` that's a little surprising. Going by the
output of :code:`ls`, we should be able to read this file. After all,
:code:`sudo` makes us root, so we should be able to read any file. However,
the read request is also filtered by the host OS, where it fails: in the host,
recall that the whole virtual machine is running as :code:`reidpr`, who is not
allowed to read :code:`foo`. However, he is allowed to read :code:`bar`, so
that call succeeds.

We'll explore two more examples. First, let's create a file within the guest,
again as unprivileged :code:`charlie`::

  > echo hello baz > baz
  -bash: baz: Permission denied
  > ls -ld
  drwxrwsr-x 2 1001 1001 4096 May 16 11:17 .

This again fails because the guest kernel sees that the directory is not
writeable by user :code:`charlie`.

One workaround is to make the directory world-writable. In these cases, one
also typically sets the `sticky bit
<http://en.wikipedia.org/wiki/Sticky_bit>`_ on the directory; this means that
users cannot remove files they don't own, even if the directory is otherwise
writeable. For example::

  > ls -ld
  drwxrwxrwt 6 root root 160 May 16 14:22 .
  > echo hello baz > baz
  > cat baz
  hello baz
  > ls -l
  -rw-r--r-- 1 1001 1001 10 May 16 14:22 baz

So far so good. Let's continue::

  > rm -f baz
  rm: cannot remove `baz': Operation not permitted
  > sudo chmod 666 baz
  > rm -f baz
  rm: cannot remove `baz': Operation not permitted

Well, that's awkward. We just created a file and can't delete it, even though
the directory is world-writeable and we made the file world-writeable? This is
where the sticky bit comes in. Because the file is really created by QEMU on
the host, with owner 1001:1001 (i.e., :code:`reidpr:reidpr`), the guest OS
thinks we don't own it and therefore can't delete it despite the broad write
permissions, because of the sticky bit (denoted by the final :code:`t` in the
directory permissions).

Here's another good one::

  $ touch qux
  touch: setting times of `qux': Permission denied
  $ ls -l
  -rw-r--r-- 1 1001 1001 10 May 16 14:22 baz
  -rw-r--r-- 1 1001 1001  0 May 16 14:24 qux

I bet you haven't seen that error before. The file was created, but the
system call to set timestamps failed. Here's why:

#. Create file; approved by both guest and host OS.

#. Because the file is really created by the QEMU process on the host, it gets
   the default :code:`reidpr:reidpr` ownership, a.k.a. UID 1001, GID 1001.

#. Change file's timestamp. This is rejected by the guest OS because we are
   trying to change the time of a file we don't own. (The host OS would
   approve this; that is, the operation would work if we were root in the
   guest.)

**The bottom line is:** We have two operating systems enforcing permissions
using uncoordinated UID and GID sets. This leads to undesirable results. We
want jobs to be able to run unprivileged in the guest with a minimum of hassle
and without bizarre side effects.

Potential solutions
===================

There are a wide variety of potential solutions to this problem. Our
goals are to:

* Focus changes on the host side, to simplify setting up guest images. (The
  former happens once, while the latter may happen many times.)

* Minimize the leakiness of the abstraction from the user's perspective. It
  should "just work".

* Maximize separation between host and guest, to allow greatest flexibility on
  the guest side as well as reduce security exposure.

* Don't screw things up within the guest. (For example, the job user needs to
  always have access to his/her home directory.)

The following subsections list potential solutions in no particular order.

:code:`security_model=mapped`
-----------------------------

QEMU has two "security models" where filesystem metadata operations are not
exported to the host but rather stored in a special place where only guests
can see them, either extended attributes (:code:`mapped-xattr`) or hidden
directories (:code:`mapped-file`).

This solves most of the problems above, but only for files and directories
created within the guest. If externally created files are important, as they
are for Charliecloud, then it doesn't help much.

Attribute storage is also somewhat brittle, as extended attributes are ignored
by many tools, and the hidden directory attributes are by filename and thus
can be messed up by changes on the host side.

This also screws up symbolic links.

Run jobs as root
----------------

This solves the clashing permission models problem, and it's a reasonable
thing to do security-wise because privileges are sandboxed inside the guest,
but it's bad hygiene in general and risks screwing up the guest.

Turn off guest permission checks on passthrough filesystem
----------------------------------------------------------

In principle, the guest kernel could be told to ignore permissions on the
passthrough filesystem. However, this does not appear to be currently possible
in practice.

Mount with :code:`uid=foo`, :code:`gid=bar`
-------------------------------------------

Some filesystems can be mounted with remapped UID and GID specified as a mount
option. However, this seems to be only available for filesystems that don't
have any inherent notion of ownership, such as VFAT.

This is likely a fairly straightforward patch to QEMU or the kernel.

If it were possible, there might be problems with managing groups from within
the guest.

bindfs
------

:code:`bindfs` is a FUSE driver which can re-mount a filesystem with various
manipulations including UID/GID remapping.

However, it has a major performance impact, on the order of 75% in `one test
<http://www.redbottledesign.com/blog/mirroring-files-different-places-links-bind-mounts-and-bindfs>`_.

:code:`fsuid` and :code:`fsgid`
-------------------------------

Linux actually has a fourth set of active UID and GID for users, called
:code:`fsuid` and :code:`fsgid`, short for *filesystem user id* and *group
id*. These are used for filesystem interactions. Apparently they were used for
historic NFS implementations but not otherwise.

They are obscure and have weak userspace support. Setting them requires a
system call. We could do this with a short C wrapper for jobs.

Import users and groups from host
---------------------------------

This removes the problem by making the guest and hosts users and groups match.
Then, the two permissions checks will give the same result.

Problems:

* Guest users and groups must be kept up to date.

* Must deal with system users and groups that shouldn't be synced.

* Some properties shouldn't be synced.

* Hosts vary. For example, LDAP is often consistent institution-wide, but
  workstations aren't always consistent between themselves or with LDAP.
  Guests can be moved between the two zones.

Change UID before running job
-----------------------------

A dynamic variation on the above. Change the job user's UID to match the host
UID before running the job.

There are several drawbacks/risks:

#. Screwing up the guest. The job user needs to retain access to its home
   directory and any other owned files; changing the UID breaks that. It is
   impractical to comprehensively :code:`chown` all files in the guest each
   time a job is run.

   One workaround is to have two users, say :code:`charlie` and
   :code:`chextern`, one for general non-privileged use and one for running
   jobs; the latter's UID is the one that's adjusted. It could even be
   re-named to match the host username.

   With some group finesse (e.g., placing the two users in one another's `user
   private groups <https://wiki.debian.org/UserPrivateGroups>`_), the two can
   probably access one another's files with few problems.

#. This does not help in the situation where access is granted by host group
   rather than host user.

#. The non-adjusted UID (i.e., :code:`charlie`) might coincidentally be the
   same as the host UID. The probability of this happening can be reduced by
   choosing a UID unlikely to be in use.

#. Files created by :code:`charlie` on the passthrough filesystems will still
   be owned by :code:`chextern`.

Add host groups before running job
----------------------------------

Similarly, groups matching the host user's groups could be added, and the job
user added to those groups, before the job runs.

The job user should not be added to any system groups. For example, on my
workstation, I'm in group :code:`libvirtd` (gid=133), which shouldn't be
imported (recall, however, that any privilege escalation within the guest is
limited by the VM sandbox). This can be mitigated by excluding system groups.

As this augments rather than replaces existing guest configuration, the risk
of screwing up the guest is minimal.


Solution implemented in Charliecloud
====================================

.. note::

   This is a design document and is not necessarily kept up to date. Refer to
   the Charliecloud source code for what is actually done now.

1. Guests have a secondary job user whose UID is adjusted on each boot to
   match the invoking host user. (The username is not adjusted so that it can
   be referred to.) Thus, at least for files owned by the invoking host user,
   ownership will appear correct.

2. The secondary job user's primary group is similarly adjusted to match the
   GID and name of the invoking user's primary group. The primary job user
   :code:`charlie` is a member of this group.

3. Other groups the host user is in are added and adjusted as described above.
   Both the primary and secondary job users are added to these groups.

The result is that owner and group will appear correct inside the guest
for files owned by the invoking host user and whose group is a group
this user is in, respectively.

The bottom line is, users should log into the guests as :code:`charlie`, and
jobs run as :code:`charlie`. If users set up group access properly on the host
side --- group permissions equal to user permissions, which doesn't
necessarily reduce security since file groups can be the user-private group
--- then :code:`charlie` will be able to do everything necessary to run jobs.
Some situations (e.g., :code:`chmod`) require :code:`su`’ing to
:code:`chextern`.
