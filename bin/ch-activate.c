/* Copyright © Los Alamos National Security, LLC, and others. */

/* This program has two basic jobs:

     1. chroot(2) into the Charliecloud image (privileged)
     2. Run the program the user wanted (as the user)

   The implicit step is to properly drop privileges before Step 2 so that we
   really run the users program as him or her. That is, particular care is
   required because this program does not need to be exploited in order to run
   arbitrary code; doing so is the whole point.

   This program is designed to run setuid root. It will in fact refuse to run
   if invoked directly by root, because this makes validation of no privilege
   after dropping more complicated.

   It would be better to use capabilities and run setcap CAP_SYS_CHROOT rather
   than setuid. However, file capabilities depend on extended attributes,
   which are not available on NFSv3, which is a key deployment target as of
   August 2015.

   Most of the logic in this program deals with dropping privileges safely,
   which is a non-trivial task [e.g., 1]. We follow the recommendations in
   [1], supplemented by [2, 3]. More specifically, we use the setresuid(2) and
   setresgid(2) calls, which have a simpler API than the POSIX setuid(2) and
   setgid(2), and we validate the lack of privilege after dropping.

   We do not worry about:

     * Supplemental groups. Because we do not change the supplemental groups,
       nothing needs to be dropped.

     * Linux-specific fsuid and fsgid, which track euid/egid unless
       specifically changed, which we do not. Kernel bugs have existed which
       violate this invariant, but none are recent. Also, there are no
       functions to query the fsuid and fsgid (you must read files in /proc).

   While we have not deliberatedly introduced any non-portable code, this
   program is designed for Linux 2.6.32+ and is untested elsewhere.

   [1]: https://www.usenix.org/legacy/events/sec02/full_papers/chen/chen.pdf
   [2]: https://www.securecoding.cert.org/confluence/display/c/POS36-C.+Observe+correct+revocation+order+while+relinquishing+privileges
   [3]: https://www.securecoding.cert.org/confluence/display/c/POS37-C.+Ensure+that+privilege+relinquishment+is+successful

*/

#define _GNU_SOURCE  // for setresuid(2) and friends
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

void drop_privs();
void efatal(const char * msg);
void fatal(const char * msg);
void pivot(int argc, char * argv[]);
void usage();
void verify_invoking_privs();
void verify_no_privs();


/** Constants **/

// The directory to which we chroot(2). This ought to provide some options,
// though it's probably best to allow some selection from admin-defined
// options rather than open-ended chrooting.
#define CHROOT_TARGET "/chmnt"


/** Main **/

int main(int argc, char * argv[])
{
   verify_invoking_privs();
   if (argc < 2) {
      drop_privs();
      verify_no_privs();
      usage();
   }
   if (chroot(CHROOT_TARGET) != 0) { efatal("chroot() failed"); }
   if (chdir("/") != 0) { efatal("chdir() failed"); }
   drop_privs();
   verify_no_privs();
   pivot(argc, argv);
}


/** Supporting functions **/

/* Drop UID privileges and act as the invoking user. We should not have any
   group privileges, so we do not drop them. We verify this lack of group
   privilege later. */
void drop_privs()
{
   uid_t ruid = getuid();
   if (setresuid(ruid, ruid, ruid) != 0) { efatal("setresuid() failed"); }
}

void efatal(const char * msg)
{
   perror(msg);
   exit(EXIT_FAILURE);
}

void fatal(const char * msg)
{
   fputs(msg, stderr);
   fputs("\n", stderr);
   exit(EXIT_FAILURE);
}

/* Replace the current process with command and arguments starting at argv[1]
   (i.e., argv[1] is the command to exectue, argv[2] the first argument, etc.
   argv will be overwritten in order to avoid the need for copying it, because
   execvp() requires null-termination instead of an argument count. */
void pivot(int argc, char * argv[])
{
   for (int i = 0; i < argc - 1; i++)
      argv[i] = argv[i + 1];
   argv[argc - 1] = NULL;
   execvp(argv[0], argv);  // only returns if error
   efatal("execvp() failed");
}

/* Verify that the UIDs and GIDs on invocation are as expected. If not, exit
   with an error message. */
void verify_invoking_privs()
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;

   if (getresuid(&ruid, &euid, &suid) != 0) { efatal("getresuid() failed"); }
   if (getresgid(&rgid, &egid, &sgid) != 0) { efatal("getresgid() failed"); }

   // want setuid, not run directly as root
   if (ruid == 0)
      fatal("must run as normal user, not root");
   if (euid != 0 || suid != 0)
      fatal("executable must be setuid root");

   // gids should be unprivileged and the same (i.e., not setgid)
   if (egid == 0)
      fatal("will not run with GID 0");
   if (rgid != egid || sgid != egid)
      fatal("will not run setgid");
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

   if (getresuid(&ruid, &euid, &suid) != 0) { efatal("getresuid() failed"); }
   if (getresgid(&rgid, &egid, &sgid) != 0) { efatal("getresgid() failed"); }

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

/* Print a usage message and abort. */
void usage()
{
   fprintf(stderr,
      /* If we were less lazy, we'd use the executable name in argv[0]. */
      "Usage:\n"
      "\n"
      "  $ ch-activate PROGRAM [ARGS ...]\n"
      "\n"
      "chroot(2) to the pre-defined Charliecloud image mount point and then\n"
      "run PROGRAM (with optional ARGS) as the invoking user. PROGRAM can be\n"
      "an absolute pathname or found in $PATH within the image using the\n"
      "normal rules.\n");
   exit(EXIT_FAILURE);
}
