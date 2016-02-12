/* Copyright © Los Alamos National Security, LLC, and others. */

#define _GNU_SOURCE
#include <argp.h>
#include <errno.h>
#include <fcntl.h>
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
void log_ids(const char * func, int line);
void run_user_command(int argc, char * argv[], int user_cmd_start);
static error_t parse_opt(int key, char * arg, struct argp_state * state);
void setup_namespaces(const bool userns_p, const uid_t cuid, const gid_t cgid);


/** Constants and macros **/

/* The image root has been set up by ch-mount here. This is the default and
   can be changed by environment variable or command line option. */
#define NEWROOT_DEFAULT "/chmnt"

/* The old root is put here, rooted at TARGET. */
#define OLDROOT "/mnt/oldroot"

/* Number of supplemental GIDs we can deal with. */
#define SUPP_GIDS_MAX 32

/* Test some result: if not zero, exit with an error. This is a macro so we
   have access to the file and line number. */
#define TRY(x) if (x) fatal(__FILE__, __LINE__)

/* Log the current UIDs. */
#define LOG_IDS log_ids(__func__, __LINE__)


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
   { "gid",       'g', "GID", 0, "run as GID within container" },
   { "no-userns", 'n', 0,     0, "don't use user namespace" },
   { "newroot",   'r', "DIR", 0, "container root directory" },
   { "uid",       'u', "UID", 0, "run as UID within container" },
   { "verbose",   'v', 0,     0, "be more verbose" },
   { 0 }
};

struct args {
   gid_t container_gid;
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
   args.container_gid = getegid();
   args.container_uid = geteuid();
   args.newroot = getenv("CH_NEWROOT");
   if (args.newroot == NULL)
      args.newroot = NEWROOT_DEFAULT;
   args.userns = true;
   args.verbose = false;
   TRY (argp_parse(&argp, argc, argv, 0, &(args.user_cmd_start), &args));
   if (args.user_cmd_start >= argc) {
      fprintf(stderr, "%s: no command specified\n",
              program_invocation_short_name);
      exit(EXIT_FAILURE);
   }

   if (args.verbose) {
      fprintf(stderr, "newroot: %s\n", args.newroot);
      fprintf(stderr, "container uid: %u\n", args.container_uid);
      fprintf(stderr, "container gid: %u\n", args.container_gid);
      fprintf(stderr, "user namespace: %d\n", args.userns);
   }

   setup_namespaces(args.userns, args.container_uid, args.container_gid);
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

   LOG_IDS;

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

/* If verbose, print uids and gids on stderr prefixed with where. */
void log_ids(const char * func, int line)
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;
   gid_t supp_gids[SUPP_GIDS_MAX];
   int supp_gid_ct;

   if (args.verbose) {
      TRY (getresuid(&ruid, &euid, &suid));
      TRY (getresgid(&rgid, &egid, &sgid));
      fprintf(stderr, "%s %d: uids=%d,%d,%d, gids=%d,%d,%d + ", func, line,
              ruid, euid, suid, rgid, egid, sgid);
      TRY ((supp_gid_ct = getgroups(SUPP_GIDS_MAX, supp_gids)) == -1);
      for (int i = 0; i < supp_gid_ct; i++) {
         if (i > 0)
            fprintf(stderr, ",");
         fprintf(stderr, "%d", supp_gids[i]);
      }
      fprintf(stderr, "\n");
   }
}

/* Parse one command line option. Called by argp_parse(). */
static error_t parse_opt(int key, char * arg, struct argp_state * state)
{
   struct args * as = state->input;
   long l;

   switch (key) {
   case 'g':
      errno = 0;
      l = strtol(arg, NULL, 0);
      TRY (errno || l < 0);
      as->container_gid = (gid_t)l;
      break;
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
   LOG_IDS;

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
   fprintf(stderr, "%s: can't execute: %s\n", program_invocation_short_name,
           strerror(errno));
}

/* Activate the desired isolation namespaces. */
void setup_namespaces(const bool userns_p, const uid_t cuid, const gid_t cgid)
{
   int flags = CLONE_NEWIPC | CLONE_NEWNS;
   int fd;
   uid_t euid = -1;
   gid_t egid = -1;

   if (userns_p) {
      flags |= CLONE_NEWUSER;
      euid = geteuid();
      egid = getegid();
   }

   LOG_IDS;
   TRY (unshare(flags));
   LOG_IDS;

   if (userns_p) {
      /* Write UID map. What we are allowed to put here is quite limited.
         Because we do not have CAP_SETUID in the *parent* user namespace, we
         can map exactly one UID: an arbitrary container UID to our EUID in
         the parent namespace.

         This is sufficient to change our UID within the container; no
         setuid(2) or similar required. This is because the EUID of the
         process in the parent namespace is unchanged, so the kernel uses our
         new 1-to-1 map to convert that EUID into the container UID for most
         (maybe all) purposes. */
      TRY ((fd = open("/proc/self/uid_map", O_WRONLY)) == -1);
      TRY (dprintf(fd, "%d %d 1\n", cuid, euid) < 0);
      TRY (close(fd));
      LOG_IDS;

      TRY ((fd = open("/proc/self/setgroups", O_WRONLY)) == -1);
      TRY (dprintf(fd, "deny\n") < 0);
      TRY (close(fd));
      TRY ((fd = open("/proc/self/gid_map", O_WRONLY)) == -1);
      TRY (dprintf(fd, "%d %d 1\n", cgid, egid) < 0);
      TRY (close(fd));
      LOG_IDS;
   }
}
