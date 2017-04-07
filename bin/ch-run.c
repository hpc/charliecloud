/* Copyright © Los Alamos National Security, LLC, and others. */

/* Note: This program does not bother to free memory allocations, since they
   are modest and the program is short-lived. */

#define _GNU_SOURCE
#include <argp.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <sched.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "charliecloud.h"

void enter_udss(char * newroot, char ** binds, bool private_tmp);
void log_ids(const char * func, int line);
void run_user_command(int argc, char * argv[], int user_cmd_start);
static error_t parse_opt(int key, char * arg, struct argp_state * state);
void setup_namespaces(uid_t cuid, gid_t cgid);


/** Constants and macros **/

/* Host filesystems to bind. */
#define USER_BINDS_MAX 10
const char * DEFAULT_BINDS[] = { "/dev",
                                 "/etc/passwd",
                                 "/etc/group",
                                 "/etc/hosts",
                                 "/etc/resolv.conf",
                                 "/proc",
                                 "/sys",
                                 NULL };

/* Number of supplemental GIDs we can deal with. */
#define SUPP_GIDS_MAX 32

/* Maximum length of paths we're willing to deal with. (Note that
   system-defined PATH_MAX isn't reliable.) */
#define PATH_CHARS 4096

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
   { "dir",         'd', "DIR", 0,
     "mount host DIR at container /mnt/i (i starts at 0)" },
   { "gid",         'g', "GID", 0, "run as GID within container" },
   { "private-tmp", 't', 0,     0, "mount container-private tmpfs on /tmp" },
   { "uid",         'u', "UID", 0, "run as UID within container" },
   { "verbose",     'v', 0,     0, "be more verbose (debug if repeated)" },
   { "version",     'V', 0,     0, "print version and exit" },
   { 0 }
};

struct args {
   char * binds[USER_BINDS_MAX+1];
   gid_t container_gid;
   uid_t container_uid;
   char * newroot;
   bool private_tmp;
   int user_cmd_start;  // index into argv where NEWROOT is
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
   args.private_tmp = false;
   args.verbose = 0;
   TRY (setenv("ARGP_HELP_FMT", "opt-doc-col=21,no-dup-args-note", 0));
   TRY (argp_parse(&argp, argc, argv, 0, &(args.user_cmd_start), &args));
   if (args.user_cmd_start >= argc - 1)
      fatal("NEWROOT and/or CMD not specified\n");
   assert(args.binds[USER_BINDS_MAX] == NULL);  // array overrun in argp_parse?
   args.newroot = argv[args.user_cmd_start++];

   if (args.verbose) {
      fprintf(stderr, "newroot: %s\n", args.newroot);
      fprintf(stderr, "container uid: %u\n", args.container_uid);
      fprintf(stderr, "container gid: %u\n", args.container_gid);
      fprintf(stderr, "private /tmp: %d\n", args.private_tmp);
   }

   setup_namespaces(args.container_uid, args.container_gid);
   enter_udss(args.newroot, args.binds, args.private_tmp);
   run_user_command(argc, argv, args.user_cmd_start); // should never return
   exit(EXIT_FAILURE);
}


/** Supporting functions **/

/* Enter the UDSS. After this, we are inside the UDSS.

   Note that pivot_root(2) requires a complex dance to work, i.e., to avoid
   multiple undocumented error conditions. This dance is explained in detail
   in examples/syscalls/pivot_root.c. */
void enter_udss(char * newroot, char ** binds, bool private_tmp)
{
   char * base;
   char * dir;
   char * oldpath;
   char * path;
   char bin[PATH_CHARS];
   struct stat st;

   LOG_IDS;

   // Claim newroot for this namespace
   TRX (mount(newroot, newroot, NULL, MS_REC | MS_BIND | MS_PRIVATE, NULL),
        newroot);

   // Mount tmpfs on guest /home because guest root is read-only
   TRY (0 > asprintf(&path, "%s/home", newroot));
   TRY (mount(NULL, path, "tmpfs", 0, "size=4m"));
   // Bind-mount default stuff at same guest path
   for (int i = 0; DEFAULT_BINDS[i] != NULL; i++) {
      TRY (0 > asprintf(&path, "%s%s", newroot, DEFAULT_BINDS[i]));
      TRY (mount(DEFAULT_BINDS[i], path, NULL, MS_REC | MS_BIND, NULL));
   }
   // Container /tmp
   TRY (0 > asprintf(&path, "%s%s", newroot, "/tmp"));
   if (private_tmp) {
      TRY (mount(NULL, path, "tmpfs", 0, 0));
   } else {
      TRY (mount("/tmp", path, NULL, MS_REC | MS_BIND, NULL));
   }
   // Bind-mount user's home directory at /home/$USER. The main use case is
   // dotfiles.
   TRY (0 > asprintf(&path, "%s/home/%s", newroot, getenv("USER")));
   TRY (mkdir(path, 0755));
   TRY (mount(getenv("HOME"), path, NULL, MS_REC | MS_BIND, NULL));
   // Bind-mount /usr/bin/ch-ssh if it exists.
   TRY (0 > asprintf(&path, "%s/usr/bin/ch-ssh", newroot));
   if (stat(path, &st)) {
      TRY (errno != ENOENT);
   } else {
      TRY (-1 == readlink("/proc/self/exe", bin, PATH_CHARS));
      bin[PATH_CHARS-1] = 0;  // guarantee string termination
      dir = dirname(bin);
      TRY (0 > asprintf(&oldpath, "%s/ch-ssh", dir));
      TRY (mount(path, oldpath, NULL, MS_BIND, NULL));
   }
   // Bind-mount user-specified directories at guest /mnt/i, which must exist
   for (int i = 0; binds[i] != NULL; i++) {
      TRY (0 > asprintf(&path, "%s/mnt/%d", newroot, i));
      TRY (mount(binds[i], path, NULL, MS_BIND, NULL));
   }

   // Overmount / to avoid EINVAL if it's a rootfs
   TRY (NULL == (path = strdup(newroot)));
   dir = dirname(path);
   TRY (NULL == (path = strdup(newroot)));
   base = basename(path);
   TRY (mount(dir, dir, NULL, MS_REC | MS_BIND | MS_PRIVATE, NULL));
   TRY (chdir(dir));
   TRY (mount(dir, "/", NULL, MS_MOVE, NULL));
   TRY (chroot("."));
   TRY (0 > asprintf(&newroot, "/%s", base));

   // Re-mount image read-only
   TRY (mount(NULL, newroot, NULL, MS_REMOUNT | MS_BIND | MS_RDONLY, NULL));

   // Pivot into the new root
   TRY (0 > asprintf(&path, "%s/oldroot", newroot));
   TRY (chdir(newroot));
   TRY (syscall(SYS_pivot_root, newroot, path));
   TRY (chroot("."));
   TRY (umount2("/oldroot", MNT_DETACH));
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
   case 't':
      as->private_tmp = true;
      break;
   case 'u':
      errno = 0;
      l = strtol(arg, NULL, 0);
      TRY (errno || l < 0);
      as->container_uid = (uid_t)l;
      break;
   case 'V':
      version();
      exit(EXIT_SUCCESS);
      break;
   case 'v':
      as->verbose++;
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
   char * old_path, * new_path;

   LOG_IDS;

   for (int i = user_cmd_start; i < argc; i++)
      argv[i - user_cmd_start] = argv[i];
   argv[argc - user_cmd_start] = NULL;

   // Append /bin to $PATH if not already present. See FAQ.
   TRY (NULL == (old_path = getenv("PATH")));
   if (strstr(old_path, "/bin") != old_path && !strstr(old_path, ":/bin")) {
      TRY (0 > asprintf(&new_path, "%s:/bin", old_path));
      TRY (setenv("PATH", new_path, 1));
      if (args.verbose)
         fprintf(stderr, "new $PATH: %s\n", new_path);
   }

   if (args.verbose) {
      fprintf(stderr, "cmd at %d/%d:", user_cmd_start, argc);
      for (int i = 0; argv[i] != NULL; i++)
         fprintf(stderr, " %s", argv[i]);
      fprintf(stderr, "\n");
   }

   execvp(argv[0], argv);  // only returns if error
   fatal("can't execve(2) user command: %s\n", strerror(errno));
}

/* Activate the desired isolation namespaces. */
void setup_namespaces(uid_t cuid, gid_t cgid)
{
   int flags = CLONE_NEWNS|CLONE_NEWUSER;
   int fd;
   uid_t euid = -1;
   gid_t egid = -1;

   euid = geteuid();
   egid = getegid();

   LOG_IDS;
   TRY (unshare(flags));
   LOG_IDS;

   /* Write UID map. What we are allowed to put here is quite limited. Because
      we do not have CAP_SETUID in the *parent* user namespace, we can map
      exactly one UID: an arbitrary container UID to our EUID in the parent
      namespace.

      This is sufficient to change our UID within the container; no setuid(2)
      or similar required. This is because the EUID of the process in the
      parent namespace is unchanged, so the kernel uses our new 1-to-1 map to
      convert that EUID into the container UID for most (maybe all)
      purposes. */
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
