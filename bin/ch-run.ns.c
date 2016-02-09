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
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
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

/* The image root has been set up by ch-mount here. */
#define NEWROOT "/chmnt"

/* The old root is put here, rooted at TARGET. */
#define OLDROOT "/mnt/oldroot"

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

   /* pivot_root(2) fails with EINVAL in a couple of undocumented conditions:
      into shared mounts, and into any filesystem that was mounted before
      CLONE_NEWUSER. The standard trick is to recursively bind-mount NEWROOT
      over itself. */
   TRY (mount(NEWROOT, NEWROOT, NULL, MS_REC | MS_BIND | MS_PRIVATE, NULL));

   TRY (mkdir(NEWROOT OLDROOT, 0755));
   TRY (syscall(SYS_pivot_root, NEWROOT, NEWROOT OLDROOT));
   TRY (chdir("/"));
   TRY (umount2(OLDROOT, MNT_DETACH));
   TRY (rmdir(OLDROOT));

   // We need our own /dev/shm because of CLONE_NEWIPC.
   TRY (mount(NULL, "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, NULL));
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

#ifndef NO_USER_NS
   /* UID/GID maps. This is a 1-to-1 mapping. Three main principles:

      1. UID/GID = 0 mapped to invoking user. That is, root in container acts
         as the invoking user.

      2. 1 <= UID/GID <= 999 are unmapped. These are the system users and
         groups. This makes them essentially unusable, but users shouldn't use
         them anyway.

      3. UID/GID >= 1000 are mapped through unchanged. That is, normal users
         appear the same inside the container as outside.

      A possible additional step is to write "deny" to /proc/self/setgroups.
      This prevents use of setgroups(2) within the container. The uses case is
      files with permissions like "rwx---rwx", where group permissions are
      less than other. Because users essentially run as themselves within a
      user namespace -- and could simply use a different wrapper that does not
      disable setgroups(2) -- this extra step has limited value. */
#endif
}

/* Print a usage message and abort. */
void usage()
{
   fprintf(stderr, "%s: usage: FIXME\n", program_invocation_short_name);
   exit(EXIT_FAILURE);
}
