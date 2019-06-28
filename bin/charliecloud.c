/* Copyright © Los Alamos National Security, LLC, and others. */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <libgen.h>
#include <pwd.h>
#include <sched.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdbool.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "charliecloud.h"
#include "version.h"


/** Macros **/

/* Log the current UIDs. */
#define LOG_IDS log_ids(__func__, __LINE__)

/* Timeout in seconds for waiting for join semaphore. */
#define JOIN_TIMEOUT 30

/* Maximum length of paths we're willing to deal with. (Note that
   system-defined PATH_MAX isn't reliable.) */
#define PATH_CHARS 4096

/* Number of supplemental GIDs we can deal with. */
#define SUPP_GIDS_MAX 128


/** Constants **/

/* Names of verbosity levels. */
const char *VERBOSE_LEVELS[] = { "error", "warning", "info", "debug" };

/* Default bind-mounts. */
struct bind BINDS_REQUIRED[] = {
   { "/dev",             "/dev" },
   { "/etc/hosts",       "/etc/hosts" },
   { "/etc/resolv.conf", "/etc/resolv.conf" },
   { "/proc",            "/proc" },
   { "/sys",             "/sys" },
   { NULL, NULL }
};
struct bind BINDS_OPTIONAL[] = {
   { "/var/opt/cray/alps/spool", "/var/opt/cray/alps/spool" },
   { "/var/lib/hugetlbfs",       "/var/opt/cray/hugetlbfs" },
   { NULL, NULL }
};


/** External variables **/

/* Level of chatter on stderr desired (0-3). */
int verbose;


/** Global variables **/

/* Variables for coordinating --join. */
struct {
   bool winner_p;
   char *sem_name;
   sem_t *sem;
   char *shm_name;
   struct {
      pid_t winner_pid;  // access anytime after initialization (write-once)
      int proc_left_ct;  // access only while serial
   } *shared;
} join;


/** Function prototypes **/

void bind_mount(char *src, char *dst, char *newroot,
                enum bind_dep dep, unsigned long flags);
void bind_mounts(struct bind *binds, char *newroot,
                 enum bind_dep dep, unsigned long flags);
char *cat(char *a, char *b);
void enter_udss(struct container *c);
void join_begin(int join_ct, char *join_tag);
void join_namespace(pid_t pid, char *ns);
void join_namespaces(pid_t pid);
void join_end();
void log_ids(const char *func, int line);
bool path_exists(char *path);
unsigned long path_mount_flags(char *path);
void path_split(char *path, char **dir, char **base);
void sem_timedwait_relative(sem_t *sem, int timeout);
void setup_namespaces(struct container *c);
void setup_passwd(struct container *c);
void tmpfs_mount(char *dst, char *newroot, char *data);


/** Functions **/

/* Bind-mount the given path into the container image. */
void bind_mount(char *src, char *dst, char *newroot,
                enum bind_dep dep, unsigned long flags)
{
   char *dst_full = cat(newroot, dst);

   if (!path_exists(src)) {
      Te (dep == BD_OPTIONAL, "can't bind: not found: %s", src);
      return;
   }

   if (!path_exists(dst_full)) {
      Te (dep == BD_OPTIONAL, "can't bind: not found: %s", dst_full);
      return;
   }

   Zf (mount(src, dst_full, NULL, MS_REC|MS_BIND|flags, NULL),
       "can't bind %s to %s", src, dst_full);
}

/* Bind-mount a null-terminated array of struct bind objects. */
void bind_mounts(struct bind *binds, char * newroot,
                 enum bind_dep dep, unsigned long flags)
{
   for (int i = 0; binds[i].src != NULL; i++)
      bind_mount(binds[i].src, binds[i].dst, newroot, dep, flags);
}

/* Concatenate strings a and b, then return the result. */
char *cat(char *a, char *b)
{
   char *ret;

   T_ (1 <= asprintf(&ret, "%s%s", a, b));
   return ret;
}

/* Set up new namespaces or join existing namespaces. */
void containerize(struct container *c)
{
   if (c->join_pid) {
      join_namespaces(c->join_pid);
      return;
   }
   if (c->join)
      join_begin(c->join_ct, c->join_tag);
   if (!c->join || join.winner_p) {
      setup_namespaces(c);
      enter_udss(c);
   } else
      join_namespaces(join.shared->winner_pid);
   if (c->join)
      join_end();

}

/* Enter the UDSS. After this, we are inside the UDSS.

   Note that pivot_root(2) requires a complex dance to work, i.e., to avoid
   multiple undocumented error conditions. This dance is explained in detail
   in examples/syscalls/pivot_root.c. */
void enter_udss(struct container *c)
{
   char *newroot_parent, *newroot_base;

   LOG_IDS;

   path_split(c->newroot, &newroot_parent, &newroot_base);

   // Claim new root for this namespace. We do need both calls to avoid
   // pivot_root(2) failing with EBUSY later.
   bind_mount(c->newroot, c->newroot, "", BD_REQUIRED, MS_PRIVATE);
   bind_mount(newroot_parent, newroot_parent, "", BD_REQUIRED, MS_PRIVATE);
   // Bind-mount default files and directories.
   bind_mounts(BINDS_REQUIRED, c->newroot, BD_REQUIRED, MS_RDONLY);
   bind_mounts(BINDS_OPTIONAL, c->newroot, BD_OPTIONAL, MS_RDONLY);
   // /etc/passwd and /etc/group.
   if (!c->private_passwd)
      setup_passwd(c);
   // Container /tmp.
   if (c->private_tmp) {
      tmpfs_mount("/tmp", c->newroot, NULL);
   } else {
      bind_mount("/tmp", "/tmp", c->newroot, BD_REQUIRED, 0);
   }
   // Container /home.
   if (!c->private_home) {
      char *newhome;
      // Mount tmpfs on guest /home because guest root is read-only
      tmpfs_mount("/home", c->newroot, "size=4m");
      // Bind-mount user's home directory at /home/$USER. The main use case is
      // dotfiles.
      Tf (c->old_home != NULL, "cannot find home directory: is $HOME set?");
      newhome = cat("/home/", getenv("USER"));
      Z_ (mkdir(cat(c->newroot, newhome), 0755));
      bind_mount(c->old_home, newhome, c->newroot, BD_REQUIRED, 0);
   }
   // Container /usr/bin/ch-ssh.
   if (c->ch_ssh) {
      char chrun_file[PATH_CHARS];
      int len = readlink("/proc/self/exe", chrun_file, PATH_CHARS);
      T_ (len >= 0);
      Te (path_exists(cat(c->newroot, "/usr/bin/ch-ssh")),
          "--ch-ssh: /usr/bin/ch-ssh not in image");
      chrun_file[ len<PATH_CHARS ? len : PATH_CHARS-1 ] = 0; // terminate; #315
      bind_mount(cat(dirname(chrun_file), "/ch-ssh"), "/usr/bin/ch-ssh",
                 c->newroot, BD_REQUIRED, 0);
   }
   // Bind-mount user-specified directories at guest DST and|or /mnt/i,
   // which must exist.
   bind_mounts(c->binds, c->newroot, BD_REQUIRED, 0);

   // Overmount / to avoid EINVAL if it's a rootfs.
   Z_ (chdir(newroot_parent));
   Z_ (mount(newroot_parent, "/", NULL, MS_MOVE, NULL));
   Z_ (chroot("."));
   c->newroot = cat("/", newroot_base);

   // Re-mount new root read-only unless --write or already read-only.
   if (!c->writable && !(access(c->newroot, W_OK) == -1 && errno == EROFS)) {
      unsigned long flags =   path_mount_flags(c->newroot)
                            | MS_REMOUNT  // Re-mount ...
                            | MS_BIND     // only this mount point ...
                            | MS_RDONLY;  // read-only.
      Zf (mount(NULL, c->newroot, NULL, flags, NULL),
          "can't re-mount image read-only (is it on NFS?)");
   }
   // Pivot into the new root. Use /dev because it's available even in
   // extremely minimal images.
   Zf (chdir(c->newroot), "can't chdir into new root");
   Zf (syscall(SYS_pivot_root, c->newroot, cat(c->newroot, "/dev")),
       "can't pivot_root(2)");
   Zf (chroot("."), "can't chroot(2) into new root");
   Zf (umount2("/dev", MNT_DETACH), "can't umount old root");
}

/* Begin coordinated section of namespace joining. */
void join_begin(int join_ct, char *join_tag)
{
   int fd;

   join.sem_name = cat("/ch-run_", join_tag);
   join.shm_name = cat("/ch-run_", join_tag);

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
      join.shared->proc_left_ct = join_ct;
      // Keep lock; winner still serialized.
   } else {
      INFO("join: winner pid: %d", join.shared->winner_pid);
      Z_ (sem_post(join.sem));
      // Losers run in parallel (winner will be done by now).
   }
}

/* End coordinated section of namespace joining. */
void join_end()
{
   // Serialize (winner never released lock).
   if (!join.winner_p)
      sem_timedwait_relative(join.sem, JOIN_TIMEOUT);

   join.shared->proc_left_ct--;
   INFO("join: %d peers left excluding myself", join.shared->proc_left_ct);

   if (join.shared->proc_left_ct <= 0) {
      INFO("join: cleaning up IPC resources");
      Te (join.shared->proc_left_ct == 0, "expected 0 peers left but found %d",
          join.shared->proc_left_ct);
      Zf (sem_unlink(join.sem_name), "can't unlink sem: %s", join.sem_name);
      Zf (shm_unlink(join.shm_name), "can't unlink shm: %s", join.shm_name);
   }

   // Parallelize.
   Z_ (sem_post(join.sem));

   Z_ (munmap(join.shared, sizeof(*join.shared)));
   Z_ (sem_close(join.sem));

   INFO("join: done");
}

/* Join a specific namespace. */
void join_namespace(pid_t pid, char *ns)
{
   char *path;
   int fd;

   T_ (1 <= asprintf(&path, "/proc/%d/ns/%s", pid, ns));
   fd = open(path, O_RDONLY);
   if (fd == -1) {
      if (errno == ENOENT) {
         Te (0, "join: no PID %d: %s not found", pid, path);
      } else {
         Tf (0, "join: can't open %s", path);
      }
   }
   Zf (setns(fd, 0), "can't join %s namespace of pid %d", ns, pid);
}

/* Join the existing namespaces created by the join winner. */
void join_namespaces(pid_t pid)
{
   INFO("joining namespaces of pid %d", pid);
   join_namespace(pid, "user");
   join_namespace(pid, "mnt");
}

/* If verbose, print uids and gids on stderr prefixed with where. */
void log_ids(const char *func, int line)
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

/* Print a formatted message on stderr if the level warrants it. Levels:

     0 : "error"   : always print; exit unsuccessfully afterwards
     1 : "warning" : always print
     1 : "info"    : print if verbose >= 2
     2 : "debug"   : print if verbose >= 3 */
void msg(int level, char *file, int line, int errno_, char *fmt, ...)
{
   va_list ap;

   if (level > verbose)
      return;

   fprintf(stderr, "%s[%d]: ", program_invocation_short_name, getpid());

   if (fmt == NULL)
      fputs(VERBOSE_LEVELS[level], stderr);
   else {
      va_start(ap, fmt);
      vfprintf(stderr, fmt, ap);
      va_end(ap);
   }

   if (errno_)
      fprintf(stderr, ": %s (%s:%d %d)\n",
              strerror(errno_), file, line, errno_);
   else
      fprintf(stderr, " (%s:%d)\n", file, line);

   if (level == 0)
      exit(EXIT_FAILURE);
}

/* Return true if the given path exists, false otherwise. On error, exit. */
bool path_exists(char *path)
{
   struct stat sb;

   if (stat(path, &sb) == 0)
      return true;

   Tf (errno == ENOENT, "can't stat: %s", path);
   return false;
}

/* Return the mount flags of the file system containing path, suitable for
   passing to mount(2).

   This is messy because, the flags we get from statvfs(3) are ST_* while the
   flags needed by mount(2) are MS_*. My glibc has a comment in bits/statvfs.h
   that the ST_* "should be kept in sync with" the MS_* flags, and the values
   do seem to match, but there are additional undocumented flags in there.
   Also, the kernel contains a test "unprivileged-remount-test.c" that
   manually translates the flags. Thus, I wasn't comfortable simply passing
   the output of statvfs(3) to mount(2). */
unsigned long path_mount_flags(char *path)
{
   struct statvfs sv;
   unsigned long known_flags =   ST_MANDLOCK   | ST_NOATIME  | ST_NODEV
                               | ST_NODIRATIME | ST_NOEXEC   | ST_NOSUID
                               | ST_RDONLY     | ST_RELATIME | ST_SYNCHRONOUS;

   Z_ (statvfs(path, &sv));
   Ze (sv.f_flag & ~known_flags, "unknown mount flags: 0x%lx %s",
       sv.f_flag & ~known_flags, path);

   return   (sv.f_flag & ST_MANDLOCK    ? MS_MANDLOCK    : 0)
          | (sv.f_flag & ST_NOATIME     ? MS_NOATIME     : 0)
          | (sv.f_flag & ST_NODEV       ? MS_NODEV       : 0)
          | (sv.f_flag & ST_NODIRATIME  ? MS_NODIRATIME  : 0)
          | (sv.f_flag & ST_NOEXEC      ? MS_NOEXEC      : 0)
          | (sv.f_flag & ST_NOSUID      ? MS_NOSUID      : 0)
          | (sv.f_flag & ST_RDONLY      ? MS_RDONLY      : 0)
          | (sv.f_flag & ST_RELATIME    ? MS_RELATIME    : 0)
          | (sv.f_flag & ST_SYNCHRONOUS ? MS_SYNCHRONOUS : 0);
}

/* Split path into dirname and basename. */
void path_split(char *path, char **dir, char **base)
{
   char *path2;

   T_ (path2 = strdup(path));
   *dir = dirname(path2);
   T_ (path2 = strdup(path));
   *base = basename(path2);
}

/* Replace the current process with user command and arguments. */
void run_user_command(char *argv[], char *initial_dir)
{
   LOG_IDS;

   if (initial_dir != NULL)
      Zf (chdir(initial_dir), "can't cd to %s", initial_dir);

   if (verbose >= 3) {
      fprintf(stderr, "argv:");
      for (int i = 0; argv[i] != NULL; i++)
         fprintf(stderr, " \"%s\"", argv[i]);
      fprintf(stderr, "\n");
   }

   Zf (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0), "can't set no_new_privs");
   execvp(argv[0], argv);  // only returns if error
   Tf (0, "can't execve(2): %s", argv[0]);
}

/* Wait for semaphore sem for up to timeout seconds. If timeout or an error,
   exit unsuccessfully. */
void sem_timedwait_relative(sem_t *sem, int timeout)
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
void setup_namespaces(struct container *c)
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
   T_ (1 <= dprintf(fd, "%d %d 1\n", c->container_uid, euid));
   Z_ (close(fd));
   LOG_IDS;

   T_ (-1 != (fd = open("/proc/self/setgroups", O_WRONLY)));
   T_ (1 <= dprintf(fd, "deny\n"));
   Z_ (close(fd));
   T_ (-1 != (fd = open("/proc/self/gid_map", O_WRONLY)));
   T_ (1 <= dprintf(fd, "%d %d 1\n", c->container_gid, egid));
   Z_ (close(fd));
   LOG_IDS;
}

/* Build /etc/passwd and /etc/group files and bind-mount them into newroot. We
   do it this way so that we capture the relevant host username and group name
   mappings regardless of where they come from. (We used to simply bind-mount
   the host's /etc/passwd and /etc/group, but this fails for LDAP at least;
   see issue #212.) After bind-mounting, we remove them on the host side;
   they'll persist inside the container and then disappear completely when the
   latter exits. */
void setup_passwd(struct container *c)
{
   int fd;
   char *path;
   struct group *g;
   struct passwd *p;

   // /etc/passwd
   T_ (path = strdup("/tmp/ch-run_passwd.XXXXXX"));
   T_ (-1 != (fd = mkstemp(path)));
   if (c->container_uid != 0)
      T_ (1 <= dprintf(fd, "root:x:0:0:root:/root:/bin/sh\n"));
   if (c->container_uid != 65534)
      T_ (1 <= dprintf(fd, "nobody:x:65534:65534:nobody:/:/bin/false\n"));
   T_ (p = getpwuid(c->container_uid));
   T_ (1 <= dprintf(fd, "%s:x:%u:%u:%s:/home/%s:/bin/sh\n",
                    p->pw_name, c->container_uid, c->container_gid,
                    p->pw_gecos, getenv("USER")));
   Z_ (close(fd));
   bind_mount(path, "/etc/passwd", c->newroot, BD_REQUIRED, 0);
   Z_ (unlink(path));

   // /etc/group
   T_ (path = strdup("/tmp/ch-run_group.XXXXXX"));
   T_ (-1 != (fd = mkstemp(path)));
   if (c->container_gid != 0)
      T_ (1 <= dprintf(fd, "root:x:0:\n"));
   if (c->container_gid != 65534)
      T_ (1 <= dprintf(fd, "nogroup:x:65534:\n"));
   T_ (g = getgrgid(c->container_gid));
   T_ (1 <= dprintf(fd, "%s:x:%u:\n", g->gr_name, c->container_gid));
   Z_ (close(fd));
   bind_mount(path, "/etc/group", c->newroot, BD_REQUIRED, 0);
   Z_ (unlink(path));
}

/* Split string str at first instance of delimiter del. Set *a to the part
   before del, and *b to the part after. Both can be empty; if no token is
   present, set both to NULL. Unlike strsep(3), str is unchanged; *a and *b
   point into a new buffer allocated with malloc(3). This has two
   implications: (1) the caller must free(3) *a but not *b, and (2) the parts
   can be rejoined by setting *(*b-1) to del. The point here is to provide an
   easier wrapper for strsep(3). */
void split(char **a, char **b, char *str, char del)
{
   char delstr[2] = { del, 0 };
   T_ (str != NULL);
   str = strdup(str);
   *b = str;
   *a = strsep(b, delstr);
   if (*b == NULL)
      *a = NULL;
}

/* Mount a tmpfs at the given path. */
void tmpfs_mount(char *dst, char *newroot, char *data)
{
   char *dst_full = cat(newroot, dst);

   Zf (mount(NULL, dst_full, "tmpfs", 0, data),
       "can't mount tmpfs at %s", dst_full);
}

/* Report the version number. */
void version(void)
{
   fprintf(stderr, "%s\n", VERSION);
}
