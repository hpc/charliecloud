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
