/* Copyright © Los Alamos National Security, LLC, and others. */

/* Note: This program does not bother to free memory allocations, since they
   are modest and the program is short-lived. */

#define _GNU_SOURCE
#include <argp.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <linux/magic.h>
#include <sched.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

#include "charliecloud.h"

void enter_udss(char * newroot, char * oldroot, char ** binds);
void log_ids(const char * func, int line);
void run_user_command(int argc, char * argv[], int user_cmd_start);
static error_t parse_opt(int key, char * arg, struct argp_state * state);
void setup_namespaces(bool userns_p, uid_t cuid, gid_t cgid);


/** Constants and macros **/

/* The old root is put here, rooted at TARGET. */
#define OLDROOT "/mnt/oldroot"

/* Host filesystems to bind. */
#define USER_BINDS_MAX 10
const char * DEFAULT_BINDS[] = { "/dev",
                                 "/etc/passwd",
                                 "/etc/group",
                                 "/etc/hosts",
                                 "/proc",
                                 "/sys",
                                 "/tmp",
                                 NULL };

/* Number of supplemental GIDs we can deal with. */
#define SUPP_GIDS_MAX 32

/* Log the current UIDs. */
#define LOG_IDS log_ids(__func__, __LINE__)


/** Command line options **/

const char usage[] = "\
\n\
Run a command in a Charliecloud container.\n\
\v\
Example:\n\
\n\
  $ ch-run /data/foo echo hello\n\
  hello\n\
\n\
You cannot use this program to actually change your UID.";

const char args_doc[] = "NEWROOT CMD [ARG...]";

const struct argp_option options[] = {
   { "dir",       'd', "DIR", 0,
     "mount host DIR at container /mnt/i (i starts at 0)" },
   { "gid",       'g', "GID", 0, "run as GID within container" },
   { "uid",       'u', "UID", 0, "run as UID within container" },
   { "verbose",   'v', 0,     0, "be more verbose (debug if repeated)" },
   { "no-userns", 'z', 0,     0, "don't use user namespace" },
   { 0 }
};

struct args {
   char * binds[USER_BINDS_MAX+1];
   gid_t container_gid;
   uid_t container_uid;
   char * newroot;
   int user_cmd_start;  // index into argv where NEWROOT is
   bool userns;         // true if using CLONE_NEWUSER
   int verbose;
};

struct args args;
const struct argp argp = { options, parse_opt, args_doc, usage };


/** Main **/

int main(int argc, char * argv[])
{
   memset(args.binds, 0, sizeof(args.binds));
   args.container_gid = getegid();
   args.container_uid = geteuid();
   args.userns = true;
   args.verbose = 0;
   TRY (setenv("ARGP_HELP_FMT", "opt-doc-col=20,no-dup-args-note", 0));
   TRY (argp_parse(&argp, argc, argv, 0, &(args.user_cmd_start), &args));
   if (args.user_cmd_start >= argc - 1)
      fatal("NEWROOT and/or CMD not specified\n");
   assert(args.binds[USER_BINDS_MAX] == NULL);  // array overrun in argp_parse?
   args.newroot = argv[args.user_cmd_start++];

   if (args.verbose) {
      fprintf(stderr, "newroot: %s\n", args.newroot);
      fprintf(stderr, "container uid: %u\n", args.container_uid);
      fprintf(stderr, "container gid: %u\n", args.container_gid);
      fprintf(stderr, "user namespace: %d\n", args.userns);
   }

   setup_namespaces(args.userns, args.container_uid, args.container_gid);
   enter_udss(args.newroot, OLDROOT, args.binds);
   run_user_command(argc, argv, args.user_cmd_start); // should never return
   exit(EXIT_FAILURE);
}


/** Supporting functions **/

/* Enter the UDSS. After this, we are inside the UDSS and no longer have
   access to host resources except as provided.

   Note that pivot_root(2) requires a complex dance to work, i.e., to avoid
   multiple undocumented error conditions. This dance is explained in detail
   in examples/syscalls/pivot_root.c. */
void enter_udss(char * newroot, char * oldroot, char ** binds)
{
   char * guestpath;
   char * hostpath;
   struct statfs st;

   LOG_IDS;

   // Claim newroot for this namespace
   TRY (mount(newroot, newroot, NULL, MS_REC | MS_BIND | MS_PRIVATE, NULL));

   // Mount tmpfses on guest /home and /mnt because guest root is read-only
   TRY (0 > asprintf(&guestpath, "%s/mnt", newroot));
   TRY (mount(NULL, guestpath, "tmpfs", 0, "size=4m"));
   TRY (0 > asprintf(&guestpath, "%s/home", newroot));
   TRY (mount(NULL, guestpath, "tmpfs", 0, "size=4m"));
   // Bind-mount default stuff at same guest path
   for (int i = 0; DEFAULT_BINDS[i] != NULL; i++) {
      TRY (0 > asprintf(&guestpath, "%s%s", newroot, DEFAULT_BINDS[i]));
      TRY (mount(DEFAULT_BINDS[i], guestpath, NULL, MS_REC | MS_BIND, NULL));
   }
   // Bind-mount user's home directory at /home/$USER. The main use case is
   // dotfiles.
   TRY (0 > asprintf(&guestpath, "%s/home/%s", newroot, getenv("USER")));
   TRY (mkdir(guestpath, 0755));
   TRY (mount(getenv("HOME"), guestpath, NULL, MS_REC | MS_BIND, NULL));
   // Bind-mount user-specified directories at guest /mnt/i
   for (int i = 0; binds[i] != NULL; i++) {
      TRY (0 > asprintf(&guestpath, "%s/mnt/%d", newroot, i));
      TRY (mkdir(guestpath, 0755));
      TRY (mount(binds[i], guestpath, NULL, MS_BIND, NULL));
   }

   // Create an intermediate root filesystem if the one we have is the rootfs.
   TRY (statfs("/", &st));
   if (st.f_type == RAMFS_MAGIC || st.f_type == TMPFS_MAGIC) {
      char * nr_base;
      char * nr_copy;
      char * nr_dir;

      TRY (NULL == (nr_copy = strdup(newroot)));
      nr_dir = dirname(nr_copy);
      TRY (NULL == (nr_copy = strdup(newroot)));
      nr_base = basename(nr_copy);

      TRY (mount(nr_dir, nr_dir, NULL, MS_REC | MS_BIND | MS_PRIVATE, NULL));
      TRY (chdir(nr_dir));
      TRY (mount(nr_dir, "/", NULL, MS_MOVE, NULL));
      TRY (chroot("."));

      TRY (0 > asprintf(&newroot, "/%s", nr_base));
   }

   // Pivot into the new root
   TRY (0 > asprintf(&hostpath, "%s%s", newroot, oldroot));
   TRY (mkdir(hostpath, 0755));
   TRY (syscall(SYS_pivot_root, newroot, hostpath));
   TRY (chdir("/"));
   TRY (umount2(oldroot, MNT_DETACH));
   TRY (rmdir(oldroot));

   // Post pivot_root() tmpfs
   //TRY (mount(NULL, "/dev/shm", "tmpfs", 0, "size=4m"));  // for CLONE_NEWIPC
   TRY (mount(NULL, "/run", "tmpfs", 0, "size=10%"));
}

/* If verbose, print uids and gids on stderr prefixed with where. */
void log_ids(const char * func, int line)
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;
   gid_t supp_gids[SUPP_GIDS_MAX];
   int supp_gid_ct;

   if (args.verbose >= 2) {
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
   int i;
   long l;

   switch (key) {
   case 'd':
      for (i = 0; as->binds[i] != NULL; i++)
         ;
      if (i < USER_BINDS_MAX)
         as->binds[i] = arg;
      else
         fatal("--dir can be used at most %d times\n", USER_BINDS_MAX);
      break;
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
      as->verbose++;
      break;
   case 'z':
      as->userns = false;
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
   fatal("can't execute: %s\n", strerror(errno));
}

/* Activate the desired isolation namespaces. */
void setup_namespaces(bool userns_p, uid_t cuid, gid_t cgid)
{
   int flags = CLONE_NEWNS;
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
