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
#include <semaphore.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
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

/* Environment variables used for --join parameters. */
char * JOIN_CT_ENV[] =  { "OMPI_COMM_WORLD_LOCAL_SIZE",
                          "SLURM_STEP_TASKS_PER_NODE",
                          "SLURM_CPUS_ON_NODE",
                          NULL };
char * JOIN_TAG_ENV[] = { "SLURM_STEP_ID",
                          NULL };

/* Timeout in seconds for waiting for join semaphore. */
#define JOIN_TIMEOUT 30

/* Variables for coordinating --join. */
struct {
   bool winner_p;
   char * sem_name;
   sem_t * sem;
   char * shm_name;
   struct {
      pid_t winner_pid;
      int proc_left_ct;
   } * shared;
} join;


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
   { "cd",          'c', "DIR", 0, "initial working directory in container"},
   { "gid",         'g', "GID", 0, "run as GID within container" },
   { "join",        'j', 0,     0, "use same container as peer ch-run" },
   { "join-ct",      -3, "N",   0, "number of ch-run peers (implies --join)" },
   { "join-tag",     -4, "TAG", 0, "label for peer group (implies --join)" },
   { "no-home",      -2, 0,     0, "do not bind-mount your home directory"},
   { "private-tmp", 't', 0,     0, "use container-private /tmp" },
   { "uid",         'u', "UID", 0, "run as UID within container" },
   { "verbose",     'v', 0,     0, "be more verbose (debug if repeated)" },
   { "version",     'V', 0,     0, "print version and exit" },
   { "write",       'w', 0,     0, "mount image read-write"},
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
   bool join;
   int join_ct;
   char * join_tag;
   bool private_home;
   bool private_tmp;
   bool writable;
   int user_cmd_start;  // index into argv where NEWROOT is
};

void enter_udss(char * newroot, bool writeable, struct bind * binds,
                bool private_tmp, bool private_home);
bool get_first_env(char ** array, char ** name, char ** value);
void join_begin();
int join_ct();
void join_end();
void join_namespace(pid_t pid, char * ns);
void join_namespaces();
char * join_tag();
void log_ids(const char * func, int line);
void run_user_command(int argc, char * argv[], int user_cmd_start);
static error_t parse_opt(int key, char * arg, struct argp_state * state);
int parse_int(char * s, bool extra_ok, char * error_tag);
void privs_verify_invoking();
void sem_timedwait_relative(sem_t * sem, int timeout);
void setup_namespaces(uid_t cuid, gid_t cgid);

struct args args;
const struct argp argp = { options, parse_opt, args_doc, usage };


/** Main **/

int main(int argc, char * argv[])
{
   privs_verify_invoking();
   memset(args.binds, 0, sizeof(args.binds));
   args.container_gid = getegid();
   args.container_uid = geteuid();
   args.initial_working_dir = NULL;
   args.join = false;
   args.join_ct = 0;
   args.join_tag = NULL;
   args.private_home = false;
   args.private_tmp = false;
   verbose = 1;  // in charliecloud.c
   Z_ (setenv("ARGP_HELP_FMT", "opt-doc-col=25,no-dup-args-note", 0));
   Z_ (argp_parse(&argp, argc, argv, 0, &(args.user_cmd_start), &args));
   Te (args.user_cmd_start < argc - 1, "NEWROOT and/or CMD not specified");
   assert(args.binds[USER_BINDS_MAX].src == NULL);  // overrun in argp_parse?
   args.newroot = realpath(argv[args.user_cmd_start++], NULL);
   Tf (args.newroot != NULL, "couldn't resolve image path");
   if (args.join) {
      args.join_ct = join_ct();
      args.join_tag = join_tag();
   }

   INFO("verbosity: %d", verbose);
   INFO("newroot: %s", args.newroot);
   INFO("container uid: %u", args.container_uid);
   INFO("container gid: %u", args.container_gid);
   INFO("join: %d %d %s", args.join, args.join_ct, args.join_tag);
   INFO("private /tmp: %d", args.private_tmp);

   if (args.join)
      join_begin();
   if (!args.join || join.winner_p) {
      setup_namespaces(args.container_uid, args.container_gid);
      enter_udss(args.newroot, args.writable, args.binds,
                 args.private_tmp, args.private_home);
   } else
      join_namespaces();
   if (args.join)
      join_end();

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

   if (args.initial_working_dir != NULL)
      Zf (chdir(args.initial_working_dir),
          "can't cd to %s", args.initial_working_dir);
}

/* Find the first environment variable in array that is set; put its name in
   *name and its value in *value, and return true. If none are set, return
   false, and *name and *value are undefined. */
bool get_first_env(char ** array, char ** name, char ** value)
{
   for (int i = 0; array[i] != NULL; i++) {
      *name = array[i];
      *value = getenv(*name);
      if (*value != NULL)
         return true;
   }

   return false;
}

/* Begin coordinated section of namespace joining. */
void join_begin()
{
   int fd;

   T_ (1 <= asprintf(&join.sem_name, "/ch-run_%s", args.join_tag));
   T_ (1 <= asprintf(&join.shm_name, "/ch-run_%s", args.join_tag));

   // Serialize.
   join.sem = sem_open(join.sem_name, O_CREAT, 0600, 1);
   T_ (join.sem != SEM_FAILED);
   sem_timedwait_relative(join.sem, JOIN_TIMEOUT);

   // Am I the winner?
   fd = shm_open(join.shm_name, O_CREAT|O_EXCL|O_RDWR, 0600);
   if (fd > 0) {
      INFO("join: I won");
      join.winner_p = true;
      Z_ (ftruncate(fd, sizeof(*join.shared)));
   } else if (errno == EEXIST) {
      join.winner_p = false;
      fd = shm_open(join.shm_name, O_RDWR, 0);
      T_ (fd > 0);
   } else {
      T_ (0);
   }

   join.shared = mmap(NULL, sizeof(*join.shared), PROT_READ|PROT_WRITE,
                      MAP_SHARED, fd, 0);
   T_ (join.shared != NULL);
   Z_ (close(fd));

   if (join.winner_p) {
      join.shared->winner_pid = getpid();
      join.shared->proc_left_ct = args.join_ct;
      // Keep lock; winner still serialized.
   } else {
      INFO("join: winner pid: %d", join.shared->winner_pid);
      Z_ (sem_post(join.sem));
      // Losers run in parallel (winner will be done by now).
   }
}

/* Find an appropriate join count; assumes --join was specified or implied.
   Exit with error if no valid value is available. */
int join_ct()
{
   int j = 0;
   char * ev_name, * ev_value;

   if (args.join_ct != 0) {
      INFO("join: peer group size from command line");
      j = args.join_ct;
      goto end;
   }

   if (get_first_env(JOIN_CT_ENV, &ev_name, &ev_value)) {
      INFO("join: peer group size from %s", ev_name);
      j = parse_int(ev_value, true, ev_name);
      goto end;
   }

end:
   Te(j > 0, "join: no valid peer group size found");
   return j;
}

/* End coordinated section of namespace joining. */
void join_end()
{
   // Serialize (winner never released lock).
   if (!join.winner_p)
      sem_timedwait_relative(join.sem, JOIN_TIMEOUT);

   join.shared->proc_left_ct--;
   INFO("join: %d peers left excluding myself", join.shared->proc_left_ct);

   // Parallelize.
   Z_ (sem_post(join.sem));

   if (join.shared->proc_left_ct <= 0) {
      INFO("join: cleaning up IPC resources");
      Te (join.shared->proc_left_ct == 0, "expected 0 peers left but found %d",
          join.shared->proc_left_ct);
      Zf (sem_unlink(join.sem_name), "can't unlink sem: %s", join.sem_name);
      Zf (shm_unlink(join.shm_name), "can't unlink shm: %s", join.shm_name);
   }

   Z_ (munmap(join.shared, sizeof(*join.shared)));
   Z_ (sem_close(join.sem));

   INFO("join: done");
}

/* Join a specific namespace. */
void join_namespace(pid_t pid, char * ns)
{
   char * path;
   int fd;

   T_ (1 <= asprintf(&path, "/proc/%d/ns/%s", pid, ns));
   fd = open(path, O_RDONLY);
   if (fd == -1) {
      if (errno == ENOENT) {
         Te (0, "join: %s not found; is winner still running?", path);
      } else {
         Tf (0, "join: can't open %s", path);
      }
   }
   Zf (setns(fd, 0), "can't join %s namespace of pid %d", ns, pid);
}

/* Join the existing namespaces created by the join winner. */
void join_namespaces()
{
   join_namespace(join.shared->winner_pid, "user");
   join_namespace(join.shared->winner_pid, "mnt");
}

/* Find an appropriate join tag; assumes --join was specified or implied. Exit
   with error if no valid value is found. */
char * join_tag()
{
   char * tag;
   char * ev_name, * ev_value;

   if (args.join_tag != NULL) {
      INFO("join: peer group tag from command line");
      tag = args.join_tag;
      goto end;
   }

   if (get_first_env(JOIN_TAG_ENV, &ev_name, &ev_value)) {
      INFO("join: peer group tag from %s", ev_name);
      tag = ev_value;
      goto end;
   }

   INFO("join: peer group tag from getppid(2)");
   T_ (1 <= asprintf(&tag, "%d", getppid()));

end:
   Te(tag[0] != '\0', "join: peer group tag cannot be empty string");
   return tag;
}

/* If verbose, print uids and gids on stderr prefixed with where. */
void log_ids(const char * func, int line)
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;
   gid_t supp_gids[SUPP_GIDS_MAX];
   int supp_gid_ct;

   if (verbose >= 3) {
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

/* Parse an integer string arg and return the result. If an error occurs,
   print a message prefixed by error_tag and exit. If not extra_ok, additional
   characters remaining after the integer are an error. */
int parse_int(char * s, bool extra_ok, char * error_tag)
{
   char * end;
   long l;

   errno = 0;
   l = strtol(s, &end, 10);
   Tf (errno == 0, error_tag);
   Ze (end == s, "%s: no digits found", error_tag);
   if (!extra_ok)
      Te (*end == 0, "%s: extra characters after digits", error_tag);
   Te (l >= INT_MIN && l <= INT_MAX, "%s: out of range", error_tag);
   return (int)l;
}

/* Parse one command line option. Called by argp_parse(). */
static error_t parse_opt(int key, char * arg, struct argp_state * state)
{
   struct args * as = state->input;
   int i;

   switch (key) {
   case -2: // --private-home
      as->private_home = true;
      break;
   case -3: // --join-ct
      as->join = true;
      as->join_ct = parse_int(arg, false, "--join-ct");
      break;
   case -4: // --join-tag
      as->join = true;
      as->join_tag = arg;
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
      i = parse_int(arg, false, "--gid");
      Te (i >= 0, "--gid: must be non-negative");
      as->container_gid = (gid_t) i;
      break;
   case 'j':
      as->join = true;
      break;
   case 't':
      as->private_tmp = true;
      break;
   case 'u':
      i = parse_int(arg, false, "--uid");
      Te (i >= 0, "--uid: must be non-negative");
      as->container_uid = (uid_t) i;
      break;
   case 'V':
      version();
      exit(EXIT_SUCCESS);
      break;
   case 'v':
      verbose++;
      Te(verbose <= 3, "--verbose can be specified at most twice");
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

   // No UID privilege allowed either.
   T_ (euid != 0);                           // no privilege
   T_ (euid == ruid && euid == suid);        // no setuid or funny business
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
   old_path = getenv("PATH");
   if (old_path == NULL) {
      WARNING("$PATH not set");
   } else if (   strstr(old_path, "/bin") != old_path
              && !strstr(old_path, ":/bin")) {
      T_ (1 <= asprintf(&new_path, "%s:/bin", old_path));
      Z_ (setenv("PATH", new_path, 1));
      INFO("new $PATH: %s", new_path);
   }

   if (verbose >= 3) {
      fprintf(stderr, "cmd at %d/%d:", user_cmd_start, argc);
      for (int i = 0; argv[i] != NULL; i++)
         fprintf(stderr, " %s", argv[i]);
      fprintf(stderr, "\n");
   }

   Zf (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0), "can't set no_new_privs");
   execvp(argv[0], argv);  // only returns if error
   Tf (0, "can't execve(2): %s", argv[0]);
}

/* Wait for semaphore sem for up to timeout seconds. If timeout or an error,
   exit unsuccessfully. */
void sem_timedwait_relative(sem_t * sem, int timeout)
{
   struct timespec deadline;

   // sem_timedwait() requires a deadline rather than a timeout.
   Z_ (clock_gettime(CLOCK_REALTIME, &deadline));
   deadline.tv_sec += timeout;

   if (sem_timedwait(sem, &deadline)) {
      Ze (errno == ETIMEDOUT, "timeout waiting for join lock");
      Tf (0, "failure waiting for join lock");
   }
}

/* Activate the desired isolation namespaces. */
void setup_namespaces(uid_t cuid, gid_t cgid)
{
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
}
