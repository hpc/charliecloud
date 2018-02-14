/* Copyright © Los Alamos National Security, LLC, and others. */

/* Notes:

   1. This program does not bother to free memory allocations, since they are
      modest and the program is short-lived.
   2. If you change any of the setuid code, consult the FAQ for some important
      design goals. */

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
#define SUPP_GIDS_MAX 128

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
  $ ch-run /data/foo -- echo hello\n\
  hello\n\
\n\
You cannot use this program to actually change your UID.";

const char args_doc[] = "NEWROOT CMD [ARG...]";

const struct argp_option options[] = {
   { "bind",        'b', "SRC[:DST]", 0,
     "mount SRC at guest DST (default /mnt/0, /mnt/1, etc.)"},
   { "write",       'w', 0,     0, "mount image read-write"},
   { "no-home",      -2, 0,     0, "do not bind-mount your home directory"},
   { "cd",          'c', "DIR", 0, "initial working directory in container"},
#ifndef SETUID
   { "gid",         'g', "GID", 0, "run as GID within container" },
#endif
   { "is-setuid",    -1, 0,     0,
     "exit successfully if compiled for setuid, else fail" },
   { "private-tmp", 't', 0,     0, "use container-private /tmp" },
#ifndef SETUID
   { "uid",         'u', "UID", 0, "run as UID within container" },
#endif
   { "verbose",     'v', 0,     0, "be more verbose (debug if repeated)" },
   { "version",     'V', 0,     0, "print version and exit" },
   { 0 }
};

struct bind {
   char * src;
   char * dst;
};

struct args {
   struct bind binds[USER_BINDS_MAX+1];
   gid_t container_gid;
   uid_t container_uid;
   char * newroot;
   char * initial_working_dir;
   bool private_home;
   bool private_tmp;
   bool writable;
   int user_cmd_start;  // index into argv where NEWROOT is
   int verbose;
};

void enter_udss(char * newroot, bool writeable, struct bind * binds,
                bool private_tmp, bool private_home);
void log_ids(const char * func, int line);
void run_user_command(int argc, char * argv[], int user_cmd_start);
static error_t parse_opt(int key, char * arg, struct argp_state * state);
void privs_verify_invoking();
void setup_namespaces(uid_t cuid, gid_t cgid);
#ifdef SETUID
void privs_drop_permanently();
void privs_drop_temporarily();
void privs_restore();
#endif

struct args args;
const struct argp argp = { options, parse_opt, args_doc, usage };


/** Main **/

int main(int argc, char * argv[])
{
   privs_verify_invoking();
#ifdef SETUID
   privs_drop_temporarily();
#endif
   memset(args.binds, 0, sizeof(args.binds));
   args.container_gid = getgid();
   args.container_uid = getuid();
   args.initial_working_dir = NULL;
   args.private_home = false;
   args.private_tmp = false;
   args.verbose = 0;
   Z_ (setenv("ARGP_HELP_FMT", "opt-doc-col=25,no-dup-args-note", 0));
   Z_ (argp_parse(&argp, argc, argv, 0, &(args.user_cmd_start), &args));
   Te (args.user_cmd_start < argc - 1, "NEWROOT and/or CMD not specified");
   assert(args.binds[USER_BINDS_MAX].src == NULL);  // overrun in argp_parse?
   args.newroot = realpath(argv[args.user_cmd_start++], NULL);
   Tf (args.newroot != NULL, "couldn't resolve image path");

   if (args.verbose) {
      fprintf(stderr, "newroot: %s\n", args.newroot);
      fprintf(stderr, "container uid: %u\n", args.container_uid);
      fprintf(stderr, "container gid: %u\n", args.container_gid);
      fprintf(stderr, "private /tmp: %d\n", args.private_tmp);
   }

   setup_namespaces(args.container_uid, args.container_gid);
   enter_udss(args.newroot, args.writable, args.binds,
              args.private_tmp, args.private_home);

#ifdef SETUID
   privs_drop_permanently();
#endif
   run_user_command(argc, argv, args.user_cmd_start); // should never return
   exit(EXIT_FAILURE);
}


/** Supporting functions **/

/* Enter the UDSS. After this, we are inside the UDSS.

   Note that pivot_root(2) requires a complex dance to work, i.e., to avoid
   multiple undocumented error conditions. This dance is explained in detail
   in examples/syscalls/pivot_root.c. */
void enter_udss(char * newroot, bool writable, struct bind * binds,
                bool private_tmp, bool private_home)
{
   char * base;
   char * dir;
   char * oldpath;
   char * path;
   char bin[PATH_CHARS];
   struct stat st;

   LOG_IDS;

#ifdef SETUID

   privs_restore();

   // Make the whole filesystem tree private. Otherwise, there's a big mess,
   // as the manipulations of the shared mounts propagate into the parent
   // namespace. Then the mount(MS_MOVE) call below fails with EINVAL, and
   // nothing is cleaned up so the mounts are a big tangle and ch-tar2dir will
   // delete your home directory. I think this is redundant with some of the
   // below, but it doesn't seem to hurt.
   Z_ (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL));

#endif

   // Claim newroot for this namespace
   Zf (mount(newroot, newroot, NULL,
             MS_REC | MS_BIND | MS_PRIVATE, NULL), newroot);
   // Bind-mount default files and directories at the same host and guest path
   for (int i = 0; DEFAULT_BINDS[i] != NULL; i++) {
      T_ (1 <= asprintf(&path, "%s%s", newroot, DEFAULT_BINDS[i]));
      Zf (mount(DEFAULT_BINDS[i], path, NULL,
                MS_REC | MS_BIND | MS_RDONLY, NULL),
          "can't bind %s to %s", (char *) DEFAULT_BINDS[i], path);
   }
   // Container /tmp
   T_ (1 <= asprintf(&path, "%s%s", newroot, "/tmp"));
   if (private_tmp) {
      Zf (mount(NULL, path, "tmpfs", 0, 0), "can't mount tmpfs at %s", path);
   } else {
      Zf (mount("/tmp", path, NULL, MS_REC | MS_BIND, NULL),
          "can't bind /tmp to %s", path);
   }
   if (!private_home) {
      // Mount tmpfs on guest /home because guest root is read-only
      T_ (1 <= asprintf(&path, "%s/home", newroot));
      Zf (mount(NULL, path, "tmpfs", 0, "size=4m"),
          "can't mount tmpfs at %s", path);
      // Bind-mount user's home directory at /home/$USER. The main use case is
      // dotfiles.
      T_ (1 <= asprintf(&path, "%s/home/%s", newroot, getenv("USER")));
      Z_ (mkdir(path, 0755));
      Zf (mount(getenv("HOME"), path, NULL, MS_REC | MS_BIND, NULL),
          "can't bind %s to %s", getenv("HOME"), path);
   }
   // Bind-mount /usr/bin/ch-ssh if it exists.
   T_ (1 <= asprintf(&path, "%s/usr/bin/ch-ssh", newroot));
   if (stat(path, &st)) {
      T_ (errno == ENOENT);
   } else {
      T_ (-1 != readlink("/proc/self/exe", bin, PATH_CHARS));
      bin[PATH_CHARS-1] = 0;  // guarantee string termination
      dir = dirname(bin);
      T_ (1 <= asprintf(&oldpath, "%s/ch-ssh", dir));
      Zf (mount(oldpath, path, NULL, MS_BIND, NULL),
          "can't bind %s to %s", oldpath, path);
   }
   // Bind-mount user-specified directories at guest DST and|or /mnt/i,
   // which must exist
   for (int i = 0; binds[i].src != NULL; i++) {
      T_ (1 <= asprintf(&path, "%s%s", newroot, binds[i].dst));
      Zf (mount(binds[i].src, path, NULL, MS_REC | MS_BIND, NULL),
          "can't bind %s to %s", binds[i].src, path);
   }

   // Overmount / to avoid EINVAL if it's a rootfs
   T_ (path = strdup(newroot));
   dir = dirname(path);
   T_ (path = strdup(newroot));
   base = basename(path);
   Z_ (mount(dir, dir, NULL, MS_REC | MS_BIND | MS_PRIVATE, NULL));
   Z_ (chdir(dir));
   Z_ (mount(dir, "/", NULL, MS_MOVE, NULL));
   Z_ (chroot("."));
   T_ (1 <= asprintf(&newroot, "/%s", base));

   if (!writable && !(access(newroot, W_OK) == -1 && errno == EROFS)) {
      // Re-mount image read-only
      Zf (mount(NULL, newroot, NULL, MS_REMOUNT | MS_BIND | MS_RDONLY, NULL),
          "can't re-mount image read-only (is it on NFS?)");
   }
   // Pivot into the new root. Use /dev because it's available even in
   // extremely minimal images.
   T_ (1 <= asprintf(&path, "%s/dev", newroot));
   Zf (chdir(newroot), "can't chdir into new root");
   Zf (syscall(SYS_pivot_root, newroot, path), "can't pivot_root(2)");
   Zf (chroot("."), "can't chroot(2) into new root");
   Zf (umount2("/dev", MNT_DETACH), "can't umount old root");

#ifdef SETUID
   privs_drop_temporarily();
#endif

   if (args.initial_working_dir != NULL)
      Zf (chdir(args.initial_working_dir),
          "can't cd to %s", args.initial_working_dir);
}

/* If verbose, print uids and gids on stderr prefixed with where. */
void log_ids(const char * func, int line)
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;
   gid_t supp_gids[SUPP_GIDS_MAX];
   int supp_gid_ct;

   if (args.verbose >= 2) {
      Z_ (getresuid(&ruid, &euid, &suid));
      Z_ (getresgid(&rgid, &egid, &sgid));
      fprintf(stderr, "%s %d: uids=%d,%d,%d, gids=%d,%d,%d + ", func, line,
              ruid, euid, suid, rgid, egid, sgid);
      supp_gid_ct = getgroups(SUPP_GIDS_MAX, supp_gids);
      if (supp_gid_ct == -1) {
         T_ (errno == EINVAL);
         Te (0, "more than %d groups", SUPP_GIDS_MAX);
      }
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
   case -1:
#ifdef SETUID
      exit(EXIT_SUCCESS);
#else
      exit(EXIT_FAILURE);
#endif
      break;
   case -2:
      as->private_home = true;
      break;
   case 'c':
      as->initial_working_dir = arg;
      break;
   case 'b':
      for (i = 0; as->binds[i].src != NULL; i++)
         ;
      Te (i < USER_BINDS_MAX,
          "--bind can be used at most %d times", USER_BINDS_MAX);
      as->binds[i].src = strsep(&arg, ":");
      assert(as->binds[i].src != NULL);
      if (arg)
         as->binds[i].dst = arg;
      else // arg is NULL => no destination specified
         T_ (1 <= asprintf(&(as->binds[i].dst), "/mnt/%d", i));
      Te (as->binds[i].src[0] != 0, "--bind: no source provided");
      Te (as->binds[i].dst[0] != 0, "--bind: no destination provided");
      break;
   case 'g':
      errno = 0;
      l = strtol(arg, NULL, 0);
      Te (errno == 0 && l >= 0, "GID must be a non-negative integer");
      as->container_gid = (gid_t)l;
      break;
   case 't':
      as->private_tmp = true;
      break;
   case 'u':
      errno = 0;
      l = strtol(arg, NULL, 0);
      Te (errno == 0 && l >= 0, "UID must be a non-negative integer");
      as->container_uid = (uid_t)l;
      break;
   case 'V':
      version();
      exit(EXIT_SUCCESS);
      break;
   case 'v':
      as->verbose++;
      break;
   case 'w':
      as->writable = true;
      break;
   default:
      return ARGP_ERR_UNKNOWN;
   };

   return 0;
}

/* Validate that the UIDs and GIDs are appropriate for program start, and
   abort if not.

   Note: If the binary is setuid, then the real UID will be the invoking user
   and the effective and saved UIDs will be the owner of the binary.
   Otherwise, all three IDs are that of the invoking user. */
void privs_verify_invoking()
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;

   Z_ (getresuid(&ruid, &euid, &suid));
   Z_ (getresgid(&rgid, &egid, &sgid));

   // Calling the program if user is really root is OK.
   if (   ruid == 0 && euid == 0 && suid == 0
       && rgid == 0 && egid == 0 && sgid == 0)
      return;

   // Now that we know user isn't root, no GID privilege is allowed.
   T_ (egid != 0);                           // no privilege
   T_ (egid == rgid && egid == sgid);        // no setuid or funny business

   // Setuid must match the compiled mode.
#ifdef SETUID
   T_ (ruid != 0 && euid == 0 && suid == 0); // must be setuid root
#else
   T_ (euid != 0);                           // no privilege
   T_ (euid == ruid && euid == suid);        // no setuid or funny business
#endif
}

/* Drop UID privileges permanently. */
#ifdef SETUID
void privs_drop_permanently()
{
   uid_t uid_wanted, ruid, euid, suid;
   gid_t rgid, egid, sgid;

   // Drop privileges.
   uid_wanted = getuid();
   T_ (uid_wanted != 0);  // abort if real UID is root
   Z_ (setresuid(uid_wanted, uid_wanted, uid_wanted));

   // Try to regain privileges; it should fail.
   T_ (-1 == setuid(0));
   T_ (-1 == setresuid(-1, 0, -1));

   // UIDs should be unprivileged and the same.
   Z_ (getresuid(&ruid, &euid, &suid));
   T_ (ruid == uid_wanted);
   T_ (uid_wanted == ruid && uid_wanted == euid && uid_wanted == suid);

   // GIDs should be unprivileged and the same.
   Z_ (getresgid(&rgid, &egid, &sgid));
   T_ (rgid != 0);
   T_ (rgid == egid && rgid == sgid);
}
#endif // SETUID

/* Drop UID privileges temporarily; can be regained with privs_restore(). */
#ifdef SETUID
void privs_drop_temporarily()
{
   uid_t unpriv_uid = getuid();

   if (unpriv_uid == 0) {
      // Invoked as root, so descend to nobody.
      unpriv_uid = 65534;
   }

   Z_ (setresuid(-1, unpriv_uid, -1));
   T_ (unpriv_uid == geteuid());
}
#endif // SETUID

/* Restore privileges that have been dropped with privs_drop_temporarily(). */
#ifdef SETUID
void privs_restore()
{
   uid_t ruid, euid, suid;

   Z_ (setresuid(-1, 0, -1));
   Z_ (getresuid(&ruid, &euid, &suid));
}
#endif // SETUID

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
   old_path = getenv("PATH");
   if (old_path == NULL) {
      if (args.verbose)
         fprintf(stderr, "warning: $PATH not set\n");
   } else if (   strstr(old_path, "/bin") != old_path
              && !strstr(old_path, ":/bin")) {
      T_ (1 <= asprintf(&new_path, "%s:/bin", old_path));
      Z_ (setenv("PATH", new_path, 1));
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
   Tf (0, "can't execve(2) user command");
}

/* Activate the desired isolation namespaces. */
void setup_namespaces(uid_t cuid, gid_t cgid)
{
#ifdef SETUID

   // can't change IDs from invoking
   T_ (cuid == getuid());
   T_ (cgid == getgid());

   privs_restore();
   Zf (unshare(CLONE_NEWNS), "can't init mount namespace");
   privs_drop_temporarily();

#else // not SETUID

   int fd;
   uid_t euid = -1;
   gid_t egid = -1;

   euid = geteuid();
   egid = getegid();

   LOG_IDS;
   Zf (unshare(CLONE_NEWNS|CLONE_NEWUSER), "can't init user+mount namespaces");
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
   T_ (-1 != (fd = open("/proc/self/uid_map", O_WRONLY)));
   T_ (1 <= dprintf(fd, "%d %d 1\n", cuid, euid));
   Z_ (close(fd));
   LOG_IDS;

   T_ (-1 != (fd = open("/proc/self/setgroups", O_WRONLY)));
   T_ (1 <= dprintf(fd, "deny\n"));
   Z_ (close(fd));
   T_ (-1 != (fd = open("/proc/self/gid_map", O_WRONLY)));
   T_ (1 <= dprintf(fd, "%d %d 1\n", cgid, egid));
   Z_ (close(fd));
   LOG_IDS;

#endif // not SETUID
}
