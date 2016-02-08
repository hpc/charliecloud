/* Copyright © Los Alamos National Security, LLC, and others. */

/* This program enters a UDSS and sets up partial isolation using namespaces.
   By default, the basic steps are:

     1. Set up 3 of the 6 namespaces:
        * mount - filesystem isolation
        * IPC - SysV and POSIX shared memory, etc.
        * user - so root within the container is unprivileged
     2. Call pivot_root(2) to enter the UDSS (similar to chroot).
     3. Unmount the old root filesystem.
     4. exec(2) the user program.

   There are preprocessor constants to alter this behavior, documented below.

   Due to the user namespace, this program is not setuid root despite use of
   privileged system calls. This eliminates the need to safely drop privileges
   before invoking user code.

   The following container isolation mechanisms are available, but we do not
   use them:

     * UTS and network namespaces are omitted so the guest can use host
       network resources directly, without bridges and whatnot.

     * The PID namespace has a subtle quirk: the first process created become
       the namespace's init, and if it exits, the kernel sends all the other
       processes in the container SIGKILL and no more can be created -- fork()
       fails with ENOMEM. As a result, a wrapper like this one cannot use a
       plain exec() pattern but must use the more complicated fork() + exec(),
       or perhaps something based on clone(CLONE_PARENT). See e.g.:

         http://man7.org/linux/man-pages/man7/pid_namespaces.7.html
         https://bugzilla.redhat.com/show_bug.cgi?id=894623

       This introduces the need for a supervisor process to pass through
       signals and perhaps other things. We want to avoid that.

     * cgroups are not needed because we assume single-tenancy, so there
       aren't other jobs to mess up. */

#define _GNU_SOURCE
#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <unistd.h>

void enter_udss();
void escalate();
void fatal(const char * file, int line);
void log_uids(const char * func, int line);
void run_user_command(int argc, char * argv[]);
void setup_namespaces();
void try(int result);
void usage();


/** Constants **/

/* There are three mount points in play for a successful pivot_root(2) into a
   UDSS and unmount of the host filesystem.

     1. newroot  This is the already-mounted UDSS filesystem we want to use.
     2. target   Place to bind-mount newroot after CLONE_NEWUSER.
     3. oldroot  Where the old root filesystem is mounted after pivot_root.

   target would seem to be unnecessary. However, CLONE_NEWUSER|CLONE_NEWNS
   introduces some restrictions. In particular, pivot_root into a filesystem
   that was mounted before CLONE_NEWUSER fails with EINVAL. One can work
   around this by bind-mounting newroot to target before pivot_root.

   Another way to work around this would be to do all UDSS mounting after
   CLONE_NEWUSER. This requires setting up the loop device manually
   (mount(8)'s -o loop option is implemented by the mount program, not libc or
   the system call). This is not yet explored. In particular, teardown of the
   loop device might be an issue, since by the time that's needed, we've
   replaced ourselves with the user program. However, in theory, the loop
   device ought to be local to the filesystem namespace. */
#define NEWROOT "/chmnt"
#define TARGET "/mnt"
#define OLDROOT "/mnt"  // rooted at TARGET

/* If set, do not set up the user namespace. This is for testing of other
   security layers and should not be offered to normal users. It will make the
   binary unusable except for root. */
#ifdef NO_USER_NS
  #warning "SECURITY: NO_USER_NS defined: Will not set up user namespace"
#endif

/* If set, run user program as root. In principle, this is safe, because
   either (a) user namespace will protect the host or (b) escalation will fail
   unless already privileged. However, some versions of Linux are buggy in
   this regard, so this test setting should not be offered to normal users. */
#ifdef RUN_AS_ROOT
  #warning "SECURITY: RUN_AS_ROOT defined: Will run user programs as root"
#endif

/* If set, log current UIDs and capabilities at various points. */
#define DEBUG_UIDS 1


/** Macros **/

/* Test the result of a system call: if not zero, exit with an error. This is
   a macro so we have access to the file and line number. */
#define TRY(x) if (x) fatal(__FILE__, __LINE__)

/* Log the current UIDs. */
#define LOG_UIDS log_uids(__func__, __LINE__)


/** Main **/

int main(int argc, char * argv[])
{
   LOG_UIDS;
   if (argc < 2)
      usage();
   setup_namespaces();
   enter_udss();
#ifdef RUN_AS_ROOT
   escalate();
#endif
   run_user_command(argc, argv);
}


/** Supporting functions **/

/* Enter the UDSS. After this, we are inside the UDSS and no longer have
   access to host resources except as provided. */
void enter_udss(const char * image_path)
{
   char * src, dst;

   LOG_UIDS;

   TRY (mount(NEWROOT, TARGET, NULL, MS_BIND, NULL));
   TRY (syscall(SYS_pivot_root, TARGET, TARGET OLDROOT));
   TRY (chdir("/"));
   TRY (umount2(OLDROOT, MNT_DETACH));

   // Mount the ancillary filesystems. We want these to be the guest versions,
   // not host ones.
   TRY (mount(NULL, "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, NULL));
   TRY (mount(NULL, "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL));
   TRY (mount(NULL, "/run", "tmpfs", MS_NOSUID | MS_NODEV, NULL));
   TRY (mount(NULL, "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL));
   // FIXME: /dev/pts devpts, /dev/hugpages hugetblfs, /dev/mqueue mqueue
}

/* Escalate to root. This requires CAP_SETUID, which we have if either (a) we
   entered a user namespace or (b) the program was invoked by root, in which
   case it's a no-op. That is, normal users can't use this to get root. */
void escalate()
{
   LOG_UIDS;
   TRY (setresuid(0, 0, 0));
   LOG_UIDS;
}

/* Report the string expansion of errno on stderr, then exit unsuccessfully. */
void fatal(const char * file, int line)
{
   fprintf(stderr, "%s:%d: %d: %s\n", file, line, errno, strerror(errno));
   exit(EXIT_FAILURE);
}

/* If DEBUG_UIDS, print uids on stderr prefixed with where. Otherwise, no-op. */
void log_uids(const char * func, int line)
{
#ifdef DEBUG_UIDS
   uid_t ruid, euid, suid;

   TRY (getresuid(&ruid, &euid, &suid));
   fprintf(stderr, "%s %d: uids=%d,%d,%d\n", func, line, ruid, euid, suid);
#endif
}

/* Replace the current process with command and arguments starting at argv[1]
   (i.e., argv[1] is the command to exectue, argv[2] the first argument, etc.
   argv will be overwritten in order to avoid the need for copying it, because
   execvp() requires null-termination instead of an argument count. */
void run_user_command(int argc, char * argv[])
{
   LOG_UIDS;
   for (int i = 0; i < argc - 1; i++)
      argv[i] = argv[i + 1];
   argv[argc - 1] = NULL;
   execvp(argv[0], argv);  // only returns if error
   fprintf(stderr, "%s: can't execute: %s", program_invocation_short_name,
           strerror(errno));
}

/* Activate the desired isolation namespaces. */
void setup_namespaces()
{
   LOG_UIDS;

   // http://man7.org/linux/man-pages/man7/namespaces.7.html
   // http://man7.org/linux/man-pages/man7/user_namespaces.7.html
   TRY (unshare(CLONE_NEWUSER | CLONE_NEWIPC | CLONE_NEWNS));
   LOG_UIDS;

#ifdef NO_USER_NS
   // Set all mounts to be slave mounts. The default on systemd systems is for
   // everything to be a shared mount. This has two effects. First, mounts and
   // unmounts inside the container propagate to the host. Second,
   // pivot_root(2) will fail later with EINVAL (this is not documented). By
   // changing to slave mode, mounts and unmounts on the host will propagate
   // into the container, but not vice versa.
   //
   // unshare(CLONE_NEWUSER) does this for us.
   //
   // See e.g.:
   //   https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=739593
   //   https://www.kernel.org/doc/Documentation/filesystems/sharedsubtree.txt
   TRY (mount(NULL, "/", NULL, MS_REC|MS_SLAVE, NULL));
#endif
}

/* Print a usage message and abort. */
void usage()
{
   fprintf(stderr, "%s: usage: FIXME\n", program_invocation_short_name);
   exit(EXIT_FAILURE);
}
