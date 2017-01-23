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
