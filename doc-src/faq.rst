Frequently asked questions (FAQ)
********************************

.. contents::
   :depth: 2
   :local:


My app needs to write to :code:`/var/log`, :code:`/run`, etc.
=============================================================

Because the image is mounted read-only, log files, caches, and other stuff
needs to go somewhere else. :code:`/tmp` is often a good choice. You have two
options:

1. Use :code:`RUN` commands in your Dockerfile to create symlinks that point
   somewhere writeable.

2. Configure the application to use a different directory.


Tarball build fails with "No command specified"
===============================================

The full error from :code:`ch-docker2tar` or :code:`ch-build2dir` is::

  docker: Error response from daemon: No command specified.

You will also see it with various plain Docker commands.

This happens when there is no default command specified. Some base images
specify one (e.g., Debian) and others don't (e.g., Alpine). Docker requires
this even for commands that don't seem like they should need it, such as
:code:`docker create` (which is what trips up Charliecloud).

The solution is to add a default command to your Dockerfile, such as
:code:`CMD ["true"]`.


:code:`--uid 0` lets me read files I can't otherwise!
=====================================================

Some permission bits can give a surprising result with a container UID of 0.
For example::

  $ whoami
  reidpr
  $ echo surprise > ~/cantreadme
  $ chmod 000 ~/cantreadme
  $ ls -l ~/cantreadme
  ---------- 1 reidpr reidpr 9 Oct  3 15:03 /home/reidpr/cantreadme
  $ cat ~/cantreadme
  cat: /home/reidpr/cantreadme: Permission denied
  $ ch-run /data/$USER.hello cat ~/cantreadme
  cat: /home/reidpr/cantreadme: Permission denied
  $ ch-run --uid 0 /data/$USER.hello cat ~/cantreadme
  surprise

At first glance, it seems that we've found an escalation -- we were able to
read a file inside a container that we could not read on the host! That seems
bad.

However, what is really going on here is more prosaic but complicated:

1. After :code:`unshare(CLONE_NEWUSER)`, :code:`ch-run` gains all capabilities
   inside the namespace. (Outside, capabilities are unchanged.)

2. This include :code:`CAP_DAC_OVERRIDE`, which enables a process to
   read/write/execute a file or directory mostly regardless of its permission
   bits. (This is why root isn't limited by permissions.)

3. Within the container, :code:`exec(2)` capability rules are followed.
   Normally, this essentially means that all capabilities are dropped when
   :code:`ch-run` replaces itself with the user command. However, if EUID is 0
   --- which it is inside the namespace given :code:`--uid 0` --- then the
   subprocess keeps all its capabilities. (This makes sense: if root creates a
   new process, it stays root.)

4. :code:`CAP_DAC_OVERRIDE` within a user namespace is honored for a file or
   directory only if its UID and GID are both mapped. In this case,
   :code:`ch-run` maps :code:`reidpr` to container :code:`root` and group
   :code:`reidpr` to itself.

5. Thus, files and directories owned by the host EUID and EGID (here
   :code:`reidpr:reidpr`) are available for all access with :code:`ch-run
   --uid 0`.

This isn't a problem. The quirk applies only to files owned by the invoking
user, because :code:`ch-run` is unprivileged outside the namespace, and thus
he or she could simply :code:`chmod` the file to read it. That is, access
inside and outside the container remains equivalent.

References:

* http://man7.org/linux/man-pages/man7/capabilities.7.html
* http://lxr.free-electrons.com/source/kernel/capability.c?v=4.2#L442
* http://lxr.free-electrons.com/source/fs/namei.c?v=4.2#L328


Why is :code:`/bin` being added to my :code:`$PATH`?
====================================================

Newer Linux distributions replace some root-level directories, such as
:code:`/bin`, with symlinks to their counterparts in :code:`/usr`, e.g.::

  $ ls -l /bin
  lrwxrwxrwx 1 root root 7 Jan 13 15:46 /bin -> usr/bin

Some of these (e.g., Fedora 24) have also dropped :code:`/bin` from the
default :code:`$PATH`. This is a problem when the guest OS does *not* have a
merged :code:`/usr` (e.g., Debian 8 "Jessie").

While Charliecloud's general philosophy is not to manipulate environment
variables, in this case, guests can be severely broken if :code:`/bin` is not
in :code:`$PATH`. Thus, we add it if it's not there.

Further reading:

  * `The case for the /usr Merge <https://www.freedesktop.org/wiki/Software/systemd/TheCaseForTheUsrMerge/>`_
  * `Fedora <https://fedoraproject.org/wiki/Features/UsrMove>`_
  * `Debian <https://wiki.debian.org/UsrMerge>`_


How does setuid mode work?
==========================

As noted above, :code:`ch-run` has a transition mode that uses setuid-root
privileges instead of user namespaces. The goal of this mode is to let sites
evaluate Charliecloud even if they do not have Linux kernels that support user
namespaces readily available. We plan to remove this code once user namespaces
are more widely available, and we encourage sites to use the unprivileged,
non-setuid mode in production.

We haven taken care to (1) drop privileges temporarily upon program start and
only re-acquire them when needed and (2) drop privileges permanently before
executing user code. In order to reliably verify the latter, :code:`ch-run` in
setuid mode will refuse to run if invoked directly by root.

It may be better to use capabilities and setcap rather than setuid. However,
this also relies on newer features, which would hamper the goal of broadly
available testing. For example, NFSv3 does not support extended attributes,
which are required for setcap files.

Dropping privileges safely requires care. We follow the recommendations in
"`Setuid demystified
<https://www.usenix.org/legacy/events/sec02/full_papers/chen/chen.pdf>`_" as
well as the `system call ordering
<https://www.securecoding.cert.org/confluence/display/c/POS36-C.+Observe+correct+revocation+order+while+relinquishing+privileges>`_
and `privilege drop verification
<https://www.securecoding.cert.org/confluence/display/c/POS37-C.+Ensure+that+privilege+relinquishment+is+successful>`_
recommendations of the SEI CERT C Coding Standard.

We do not worry about the Linux-specific :code:`fsuid` and :code:`fsgid`,
which track :code:`euid`/:code:`egid` unless specifically changed, which we
don't do. Kernel bugs have existed that violate this invariant, but none are
recent.


:code:`ch-run` fails with "can't re-mount image read-only"
==========================================================

Normally, :code:`ch-run` re-mounts the image directory read-only within the
container. This fails if the image resides on certain filesystems, such as NFS
(see `issue #9 <https://github.com/hpc/charliecloud/issues/9>`_). There are
two solutions:

1. Unpack the image into a different filesystem, such as :code:`tmpfs` or
   local disk. Consult your local admins for a recommendation.

2. Use the :code:`-w` switch to leave the image mounted read-write. Note that
   this has may have an impact on reproducibility (because the application can
   change the image between runs) and/or stability (if there are multiple
   application processes and one writes a file in the image that another is
   reading or writing).
