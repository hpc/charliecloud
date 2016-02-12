chrun is a user program to run code in a user-defined software stack (UDSS).
Three of the six namespaces are used:

  mount  filesystem isolation
  IPC    SysV/POSIX shared memory, etc.
  user   keep root within the container unprivileged

Due to the user namespace, chrun is not setuid root despite its use of
privileged system calls. This eliminates the need to safely drop privileges
before invoking user code.

By default, the user command is run with all UIDs set to the effective user ID
of the caller. This can be changed with the --uid option. In either case, this
container UID is mapped to the EUID of the caller; i.e., the user command can
believe it has an arbitrary UID, but the EUID of the caller outside the
container is used for access control. No other UIDs are mapped and will appear
as 'nobody'.

For example, let's try to use this mechanism to get a copy of memory:

  $ ch-run --uid 0 whoami
  root
  $ ch-run --uid 0 dd if=/dev/mem of=~/my-copy-of-memory
  dd: failed to open ‘/dev/mem’: Permission denied

GIDs 1000 and greater inside the container are mapped to the same GID outside
the container. That is, user groups should appear the same inside and outside
the container, and system groups will appear as 'nogroup'. Writing such a map
is a privileged operation in the parent namespace, so it is accomplished using
a setuid helper.

Bind mounts inside the new root are kept. This is used to support specific
host resources such as /sys, /proc, /etc/passwd, along with user-specified
directories.

There are other container isolation mechanisms, but we do not use them:

  * cgroups are not needed because we assume single-tenancy, so there aren't
    other users to mess up.

  * UTS and network namespaces are omitted so the guest can use host network
    resources directly, without bridges and whatnot.

  * The PID namespace has a subtle quirk: the first process created become the
    namespace's init, and if it exits, the kernel sends all the other
    processes in the container SIGKILL and no more can be created -- fork()
    fails with ENOMEM. As a result, a wrapper like this one cannot use a plain
    exec() pattern but must use the more complicated fork() + exec(), or
    perhaps something based on clone(CLONE_PARENT). See e.g.:

      http://man7.org/linux/man-pages/man7/pid_namespaces.7.html
      https://bugzilla.redhat.com/show_bug.cgi?id=894623

    This introduces the need for a supervisor process to proxy signals and
    perhaps other things. We want to avoid this complexity.

Further reading:

  http://man7.org/linux/man-pages/man7/namespaces.7.html
  http://man7.org/linux/man-pages/man7/user_namespaces.7.html

Some filesystem permission tests can give a surprising result with a container
UID of 0. For example:

  $ whoami
  reidpr
  $ mkdir /tmp/foo
  $ echo surprise > /tmp/foo/cantreadme
  $ chmod 000 /tmp/foo/cantreadme
  $ ls -l /tmp/foo/cantreadme
  ---------- 1 reidpr reidpr 9 Feb 12 13:53 /tmp/foo/cantreadme
  $ cat /tmp/foo/cantreadme
  cat: /tmp/foo/cantreadme: Permission denied
  $ sudo ch-mount /data/reidpr.chtest.img /tmp/foo
  $ ch-run cat /mnt/0/cantreadme
  cat: /mnt/0/cantreadme: Permission denied
  $ ch-run -u0 cat /mnt/0/cantreadme
  surprise

At first glance, this seems rather scary -- we got access to a file inside the
container that we didn't have outside! However, what is actually going on is
rather more prosaic:

  1. After unshare(CLONE_NEWUSER), ch-run gains all capabilities inside the
     namespace. (Outside, capabilities are unchanged.)

  2. This includes CAP_DAC_OVERRIDE, which enables a process to
     read/write/execute a file or directory roughly regardless of its
     permission bits. (This is why root isn't limited by permissions.)

  3. Within the container, execve(2) capability rules are followed. Normally,
     this means roughly that all capabilities are dropped. However, if EUID is
     0, then the subprocess keeps all its capabilities. (This makes sense --
     if root creates a new process, it stays root.)

  4. CAP_DAC_OVERRIDE within a user namespace is honored for a file or
     directory only if its UID and GID are both mapped. In the above case,
     ch-run maps user reidpr to root (because -u0) and group reidpr to reidpr.

  5. Thus, files and directories owned by reidpr:reidpr are available for all
     access with chrun -u0.

This is OK, though. Because the invoking user (reidpr in this case) owns the
file, s/he should simply chown it. That is, access inside and outside the
container remains equivalent, but with fewer steps inside.

References:

  http://man7.org/linux/man-pages/man7/capabilities.7.html
  http://lxr.free-electrons.com/source/kernel/capability.c?v=4.2#L442
  http://lxr.free-electrons.com/source/fs/namei.c?v=4.2#L328
