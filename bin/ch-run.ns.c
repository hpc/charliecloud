/* Copyright © Los Alamos National Security, LLC, and others. */

#define _GNU_SOURCE
#include <argp.h>
#include <errno.h>
#include <sched.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

void enter_udss(const char * newroot, const char * oldroot);
void fatal(const char * file, int line);
void log_uids(const char * func, int line);
void run_user_command(int argc, char * argv[], int user_cmd_start);
static error_t parse_opt(int key, char * arg, struct argp_state * state);
void setup_namespaces(const bool userns_p);


/** Constants and macros **/

/* The image root has been set up by ch-mount here. This is the default and
   can be changed by environment variable or command line option. */
#define NEWROOT_DEFAULT "/chmnt"

/* The old root is put here, rooted at TARGET. */
#define OLDROOT "/mnt/oldroot"

/* Test some result: if not zero, exit with an error. This is a macro so we
   have access to the file and line number. */
#define TRY(x) if (x) fatal(__FILE__, __LINE__)

/* Log the current UIDs. */
#define LOG_UIDS log_uids(__func__, __LINE__)


/** Command line options **/

const char usage[] = "\
\n\
Run a command with new root directory and partial isolation using namespaces.\n\
\v\
Example:\n\
\n\
  $ ch-run echo hello world\n\
  hello world\n\
\n\
Normal users will rarely need any of the options. In particular, the new root\n\
directory is managed by system administrators.\n\
\n\
You cannot use this program to actually change your UID.";

static char args_doc[] = "CMD [ARGS ...]";

static struct argp_option options[] = {
   { "no-userns", 'n', 0,     0, "don't use user namespace" },
   { "newroot",   'r', "DIR", 0, "container root directory" },
   { "uid",       'u', "UID", 0, "run as UID within container" },
   { "verbose",   'v', 0,     0, "be more verbose" },
   { 0 }
};

struct args {
   uid_t container_uid;
   char * newroot;
   int user_cmd_start;  // index into argv where user command and args start
   bool userns;         // true if using CLONE_NEWUSER
   bool verbose;
};

struct args args;
static struct argp argp = { options, parse_opt, args_doc, usage };


/** Main **/

int main(int argc, char * argv[])
{
   args.container_uid = geteuid();
   args.newroot = getenv("CH_NEWROOT");
   if (args.newroot == NULL)
      args.newroot = NEWROOT_DEFAULT;
   args.userns = true;
   args.verbose = false;
   argp_parse(&argp, argc, argv, 0, &(args.user_cmd_start), &args);

   if (args.verbose) {
      fprintf(stderr, "newroot: %s\n", args.newroot);
      fprintf(stderr, "container uid: %u\n", args.container_uid);
      fprintf(stderr, "user namespace: %d\n", args.userns);
   }

   setup_namespaces(args.userns);
   //TRY (setresuid(args.container_uid, args.container_uid, args.container_uid));
   enter_udss(args.newroot, OLDROOT);
   run_user_command(argc, argv, args.user_cmd_start);
}


/** Supporting functions **/

/* Enter the UDSS. After this, we are inside the UDSS and no longer have
   access to host resources except as provided. */
void enter_udss(const char * newroot, const char * oldroot)
{
   char * host_oldroot;
   const char * guest_oldroot = oldroot;

   LOG_UIDS;

   /* pivot_root(2) fails with EINVAL in a couple of undocumented conditions:
      into shared mounts, and into any filesystem that was mounted before
      CLONE_NEWUSER. The standard trick is to recursively bind-mount NEWROOT
      over itself. */
   TRY (mount(args.newroot, args.newroot, NULL,
              MS_REC | MS_BIND | MS_PRIVATE, NULL));

   TRY (asprintf(&host_oldroot, "%s/%s", newroot, oldroot) < 0);
   TRY (mkdir(host_oldroot, 0755));
   TRY (syscall(SYS_pivot_root, newroot, host_oldroot));
   TRY (chdir("/"));
   TRY (umount2(guest_oldroot, MNT_DETACH));
   TRY (rmdir(guest_oldroot));

   // We need our own /dev/shm because of CLONE_NEWIPC.
   TRY (mount(NULL, "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, NULL));
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
   uid_t ruid, euid, suid;

   if (args.verbose) {
      TRY (getresuid(&ruid, &euid, &suid));
      fprintf(stderr, "%s %d: uids=%d,%d,%d\n", func, line, ruid, euid, suid);
   }
}

/* Parse one command line option. Called by argp_parse(). */
static error_t parse_opt(int key, char * arg, struct argp_state * state)
{
   struct args * as = state->input;
   long l;

   switch (key) {
   case 'n':
      as->userns = false;
      break;
   case 'r':
      as->newroot = arg;
      break;
   case 'u':
      errno = 0;
      l = strtol(arg, NULL, 0);
      TRY (errno || l < 0);
      as->container_uid = (uid_t)l;
      break;
   case 'v':
      as->verbose = true;
      break;
   default:
      return ARGP_ERR_UNKNOWN;
   };

   return 0;
}

/* Replace the current process with user command and arguments. argv will be
   overwritten in order to avoid the need for copying it, because execvp()
   requires null-termination instead of an argument count. */
void run_user_command(int argc, char * argv[], int user_cmd_start)
{
   LOG_UIDS;

   for (int i = user_cmd_start; i < argc; i++)
      argv[i - user_cmd_start] = argv[i];
   argv[argc - user_cmd_start] = NULL;

   if (args.verbose) {
      fprintf(stderr, "cmd at %d/%d:", user_cmd_start, argc);
      for (int i = 0; argv[i] != NULL; i++)
         fprintf(stderr, " %s", argv[i]);
      fprintf(stderr, "\n");
   }

   execvp(argv[0], argv);  // only returns if error
   fprintf(stderr, "%s: can't execute: %s", program_invocation_short_name,
           strerror(errno));
}

/* Activate the desired isolation namespaces. */
void setup_namespaces(const bool userns_p)
{
   int flags = CLONE_NEWIPC | CLONE_NEWNS;

   if (userns_p)
      flags |= CLONE_NEWUSER;

   LOG_UIDS;
   TRY (unshare(flags));
   LOG_UIDS;

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
}
