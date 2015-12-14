/* Copyright © Los Alamos National Security, LLC, and others. */

/* This program enters a UDSS and sets up partial isolation using namespaces.
   The basic steps are:

     1. Set up 3 of the 6 namespaces:
        * mount - filesystem isolation
        * IPC - SysV and POSIX shared memory, etc.
        * user - so privilege escalation doesn't count
     2. Call pivot_root(2) to enter the UDSS (similar to chroot).
     3. Unmount the old root.
     4. Drop privileges.
     5. exec(2) the user program.

   Why not use other common container isolation mechanisms too?

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

     * cgroups are not needed because we assume single-tenancy, so there
       aren't other jobs to mess up.

   This program is designed to run setuid root. It will in fact refuse to run
   if invoked directly by root, because this makes validation of no privilege
   after dropping more complicated. (See PWN_ME_NOW below for an exception.)

   Note that pivot_root(2) requires CAP_SYS_ADMIN, so there is no advantage to
   running setcap rather than setuid.

   Much of the logic in this program deals with dropping privileges safely,
   which is a non-trivial task [e.g., 1]. We follow the recommendations in
   [1], supplemented by [2, 3]. More specifically, we use the GNU extensions
   setresuid(2) and setresgid(2) calls, which have a simpler API than the
   POSIX setuid(2) and setgid(2), and we validate the lack of privilege after
   dropping.

   We do not worry about:

     * Supplemental groups. Because we do not change the supplemental groups,
       nothing needs to be dropped.

     * Linux-specific fsuid and fsgid, which track euid/egid unless
       specifically changed, which we do not. Kernel bugs have existed which
       violate this invariant, but none are recent. Also, there are no
       functions to query the fsuid and fsgid (you must read files in /proc).

   This program requires Linux 3.10+ for user namespace support.

   [1]: https://www.usenix.org/legacy/events/sec02/full_papers/chen/chen.pdf
   [2]: https://www.securecoding.cert.org/confluence/display/c/POS36-C.+Observe+correct+revocation+order+while+relinquishing+privileges
   [3]: https://www.securecoding.cert.org/confluence/display/c/POS37-C.+Ensure+that+privilege+relinquishment+is+successful

*/

#define _GNU_SOURCE
#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <unistd.h>

void drop_privs();
void efatal(const char * msg);
void enter_udss();
void fatal(const char * msg);
void run_user_command(int argc, char * argv[]);
void setup_namespaces();
void usage();
void verify_invoking_privs();
void verify_no_privs();


/** Constants **/

/* The directory to which we chroot. This ought to provide some options,
   though it's probably best to allow some selection from admin-defined
   options rather than open-ended chrooting.

   The UDSS must already be mounted here, for two reasons. First,
   loop-mounting a file requires a bunch of setup in userspace (i.e.,
   mount(8)'s -o loop option is implemented by the mount program, not libc or
   the system call). Second, the loop device would still have to be cleaned up
   after we are done; at that point, we're running unprivileged and have
   replaced ourselves with the user program. */
#define CHROOT_TARGET "/chmnt"

/* Where to put the old (host) root on pivot. */
#define CHROOT_PUT_OLD CHROOT_TARGET "/mnt"

/* If set, don't drop privileges before running the user program. This mode is
   grossly insecure. It is for testing what the user can do should he/she
   escalate privileges. See verify_invoking_privs() for safety checks. Don't
   change this file; instead, use the -D switch when compiling. */
#ifdef PWN_ME_NOW
  #warning "SECURITY: PWN_ME_NOW defined: Will run user programs as root"
#endif

/* Paths to keep inside the container; order host path, guest mount point,
   append username (if non-NULL). FIXME: This should be moved to a
   configuration file or something. */
const char * const HOST_PATHS [] = {
   // directories
   "/data",  "/host/1", NULL,
   "/data2", "/host/2", NULL,
   "/dev",   "/dev",    NULL,
   "/home/", "/home/",  "",
   "/tmp",   "/tmp",    NULL,
   // files
   "/etc/passwd", "/etc/passwd", NULL,
   "/etc/group",  "/etc/group",  NULL,
   "/etc/hosts",  "/etc/hosts",  NULL,
   NULL
};


/** Main **/

int main(int argc, char * argv[])
{
   verify_invoking_privs();
   if (argc < 2) {
#ifndef PWN_ME_NOW
      drop_privs();
      verify_no_privs();
#endif
      usage();
   }
   setup_namespaces();
   enter_udss();
#ifndef PWN_ME_NOW
   drop_privs();
   verify_no_privs();
#endif
   run_user_command(argc, argv);
}


/** Supporting functions **/

/* Drop UID privileges and act as the invoking user. We should not have any
   group privileges, so we do not drop them. We verify this lack of group
   privilege later. */
void drop_privs()
{
   uid_t ruid = getuid();
   if (setresuid(ruid, ruid, ruid)) efatal("setresuid");
}

/* Report the string expansion of errno on stderr, then exit unsuccessfully. */
void efatal(const char * msg)
{
   fprintf(stderr, "%s: %d: ", program_invocation_short_name, errno);
   perror(msg);
   exit(EXIT_FAILURE);
}

/* Enter the UDSS. After this, we are inside the UDSS and no longer have
   access to host resources except as provided. */
void enter_udss(const char * image_path)
{
   char * src, dst;

   if (syscall(SYS_pivot_root, CHROOT_TARGET, CHROOT_PUT_OLD))
      efatal("pivot_root");
   if (chdir("/")) efatal("chdir(\"/\")");

   // Move the host filesystems and files that we want to keep to their normal
   // places.
   while (1) {
      src = 
   }

   // Mount the ancillary filesystems. We want these to be the guest versions,
   // not host ones.
   if (mount(NULL, "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, NULL))
      efatal("mount(\"/dev/shm\")");
   if (mount(NULL, "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL))
      efatal("mount(\"/proc\")");
   if (mount(NULL, "/run", "tmpfs", MS_NOSUID | MS_NODEV, NULL))
      efatal("mount(\"/run\")");
   if (mount(NULL, "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL))
      efatal("mount(\"/sys\")");

   // Unmount the rest of the host
   if (umount2("/mnt", MNT_DETACH)) efatal("umount2(\"/mnt\")");
}

/* filesystems on stderr and exit unsuccessfully. */
void fatal(const char * msg)
{
   fprintf(stderr, "%s: %d: %s\n", program_invocation_short_name, errno, msg);
   exit(EXIT_FAILURE);
}

/* Replace the current process with command and arguments starting at argv[1]
   (i.e., argv[1] is the command to exectue, argv[2] the first argument, etc.
   argv will be overwritten in order to avoid the need for copying it, because
   execvp() requires null-termination instead of an argument count. */
void run_user_command(int argc, char * argv[])
{
   for (int i = 0; i < argc - 1; i++)
      argv[i] = argv[i + 1];
   argv[argc - 1] = NULL;
   execvp(argv[0], argv);  // only returns if error
   efatal("execvp() failed");
}

/* Activate the desired isolation namespaces. */
void setup_namespaces()
{
   // http://man7.org/linux/man-pages/man7/namespaces.7.html
   if (unshare(CLONE_NEWIPC | CLONE_NEWNS))
      efatal("unshare");

   // Set all mounts to be slave mounts. The default on systemd systems is for
   // everything to be a shared mount. This has two effects. First, mounts and
   // unmounts inside the container propagate to the host. Second,
   // pivot_root(2) will fail later with EINVAL (this is not documented). By
   // changing to slave mode, mounts and unmounts on the host will propagate
   // into the container, but not vice versa.
   //
   // See e.g.:
   //   https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=739593
   //   https://www.kernel.org/doc/Documentation/filesystems/sharedsubtree.txt
   if (mount(NULL, "/", NULL, MS_REC|MS_SLAVE, NULL))
      efatal("mount(\"/\", MS_REC|MS_SLAVE)");
}

/* Print a usage message and abort. */
void usage()
{
   fprintf(stderr, "%s: usage: FIXME\n", program_invocation_short_name);
   exit(EXIT_FAILURE);
}

/* Verify that the UIDs and GIDs on invocation are as expected. If not, exit
   with an error message. */
void verify_invoking_privs()
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;

   if (getresuid(&ruid, &euid, &suid)) efatal("getresuid");
   if (getresgid(&rgid, &egid, &sgid)) efatal("getresgid");

   fprintf(stderr, "UIDs: real %u, effective %u, saved %u\n", ruid, euid, suid);
   fprintf(stderr, "GIDs: real %u, effective %u, saved %u\n", rgid, egid, sgid);

#ifdef PWN_ME_NOW

   if (ruid != 0 || rgid != 0)
      fatal("must run directly as root in PWN_ME_NOW mode (not setuid)");

#else

   if (ruid == 0)
      fatal("must run as normal user, not root");
   if (euid != 0 || suid != 0)
      fatal("executable must be setuid root");

   if (egid == 0)
      fatal("will not run with GID 0");
   if (rgid != egid || sgid != egid)
      fatal("will not run setgid");

#endif

}

/* Verify that we have no privileges. If not, exit with an error message. */
void verify_no_privs()
{
   uid_t uid_wanted, ruid, euid, suid;
   gid_t gid_wanted, rgid, egid, sgid;

   // try to regain privileges; it should fail
   if (setuid(0) != -1)
      fatal("restoring privileges unexpectedly succeeded");

   uid_wanted = getuid();
   gid_wanted = getgid();

   if (getresuid(&ruid, &euid, &suid) != 0) efatal("getresuid");
   if (getresgid(&rgid, &egid, &sgid) != 0) efatal("getresgid");

   // uids should be unprivileged and the same
   if (uid_wanted == 0)
      fatal("real UID unexpectedly 0");
   if (uid_wanted != ruid || uid_wanted != euid || uid_wanted != suid)
      fatal("inconsistent UID(s) found");

   // gids should be unprivileged and the same
   if (gid_wanted == 0)
      fatal("real GID unexpectedly 0");
   if (gid_wanted != rgid || gid_wanted != egid || gid_wanted != sgid)
      fatal("inconsistent GID(s) found");
}
