/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include "config.h"

#include <grp.h>
#include <pwd.h>
#include <sched.h>
#include <semaphore.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "mem.h"
#include "misc.h"
#include "core.h"
#ifdef HAVE_LIBSQUASHFUSE
#include "fuse.h"
#endif


/** Macros **/

/* Timeout in seconds for waiting for join semaphore. */
#define JOIN_TIMEOUT 30

/* Maximum length of paths we’re willing to deal with. (Note that
   system-defined PATH_MAX isn't reliable.) */
#define PATH_CHARS 4096

/* Mount point for the tmpfs used by -W. We want this to be (a) always
   available [1], (b) short, (c) not used by anything else we care about
   during container setup, and (d) not wildly confusing if users see it in an
   error message. Must be a string literal because we use C’s literal
   concatenation feature. Options considered (all of these required by FHS):

      /boot       Not present if host is booted in some strange way?
      /etc        Likely very reliable but seems risky
      /mnt        Used for images on GitHub Actions and causes CI failures
      /opt        Seems very omittable
      /srv        I’ve never actually seen it used; reliable?
      /var        Too aggressive?
      /var/spool  Long; omittable for lightweight hosts?

   [1]: https://www.pathname.com/fhs/pub/fhs-2.3.pdf */
#define WF_MNT "/srv"


/** Constants **/

/* Default bind-mounts. */
struct bind BINDS_DEFAULT[] = {
   { "/dev",                     "/dev",                     BD_REQUIRED },
   { "/proc",                    "/proc",                    BD_REQUIRED },
   { "/sys",                     "/sys",                     BD_REQUIRED },
   { "/etc/hosts",               "/etc/hosts",               BD_OPTIONAL },
   { "/etc/machine-id",          "/etc/machine-id",          BD_OPTIONAL },
   { "/etc/resolv.conf",         "/etc/resolv.conf",         BD_OPTIONAL },
   /* Cray bind-mounts. See #1473. */
   { "/var/lib/hugetlbfs",       "/var/lib/hugetlbfs",       BD_OPTIONAL },
   /* Cray Gemini/Aries interconnect bind-mounts. */
   { "/etc/opt/cray/wlm_detect", "/etc/opt/cray/wlm_detect", BD_OPTIONAL },
   { "/opt/cray/wlm_detect",     "/opt/cray/wlm_detect",     BD_OPTIONAL },
   { "/opt/cray/alps",           "/opt/cray/alps",           BD_OPTIONAL },
   { "/opt/cray/udreg",          "/opt/cray/udreg",          BD_OPTIONAL },
   { "/opt/cray/ugni",           "/opt/cray/ugni",           BD_OPTIONAL },
   { "/opt/cray/xpmem",          "/opt/cray/xpmem",          BD_OPTIONAL },
   { "/var/opt/cray/alps",       "/var/opt/cray/alps",       BD_OPTIONAL },
   /* Cray Shasta/Slingshot bind-mounts. */
   { "/var/spool/slurmd",        "/var/spool/slurmd",        BD_OPTIONAL },
   { 0 }
};


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

/* Bind mounts done so far; canonical host paths. If null, there are none. */
char **bind_mount_paths = NULL;


/** Function prototypes (private) **/

void bind_mount(const char *src, const char *dst, enum bind_dep,
                const char *newroot, unsigned long flags, const char *scratch);
void bind_mounts(const struct bind *binds, const char *newroot,
                 unsigned long flags, const char * scratch);
void join_begin(const char *join_tag);
void join_end(int join_ct);
void mounts_setup(struct container *c);
void namespace_join(pid_t pid, const char *ns);
void namespaces_join(pid_t pid);
void namespaces_setup(const struct container *c, uid_t uid_out, uid_t uid_in,
                      gid_t gid_out, gid_t gid_in);
void passwd_setup(const struct container *c);
void pivot(struct container *c);
void sem_timedwait_relative(sem_t *sem, int timeout);
void tmpfs_mount(const char *dst, const char *newroot, const char *data);


/** Functions **/

/* Bind-mount the given path into the container image. */
void bind_mount(const char *src, const char *dst, enum bind_dep dep,
                const char *newroot, unsigned long flags, const char *scratch)
{
   char *dst_fullc, *newrootc;
   char *dst_full = cat(newroot, dst);

   Te (src[0] != 0 && dst[0] != 0 && newroot[0] != 0, "empty string");
   Te (dst[0] == '/' && newroot[0] == '/', "relative path");

   if (!path_exists(src, NULL, true)) {
      Te (dep == BD_OPTIONAL, "can't bind: source not found: %s", src);
      return;
   }

   if (!path_exists(dst_full, NULL, true))
      switch (dep) {
      case BD_REQUIRED:
         FATAL("can't bind: destination not found: %s", dst_full);
         break;
      case BD_OPTIONAL:
         return;
      case BD_MAKE_DST:
         mkdirs(newroot, dst, bind_mount_paths, scratch);
         break;
      }

   newrootc = realpath_(newroot, false);
   dst_fullc = realpath_(dst_full, false);
   Tf (path_subdir_p(newrootc, dst_fullc),
       "can't bind: %s not subdirectory of %s", dst_fullc, newrootc);
   if (strcmp(newroot, "/"))  // don't record if newroot is "/"
      list_append((void **)&bind_mount_paths, &dst_fullc, sizeof(char *));

   Zf (mount(src, dst_full, NULL, MS_REC|MS_BIND|flags, NULL),
       "can't bind %s to %s", src, dst_full);
}

/* Bind-mount a null-terminated array of struct bind objects. */
void bind_mounts(const struct bind *binds, const char *newroot,
                 unsigned long flags, const char * scratch)
{
   for (int i = 0; binds[i].src != NULL; i++)
      bind_mount(binds[i].src, binds[i].dst, binds[i].dep,
                 newroot, flags, scratch);
}

/* Set up new namespaces or join existing namespaces. */
void containerize(struct container *c)
{
   if (c->join_pid) {
      namespaces_join(c->join_pid);
      return;
   }
   if (c->join)
      join_begin(c->join_tag);
   if (!c->join || join.winner_p) {
      // Set up two nested user+mount namespaces: the outer so we can run
      // fusermount3 non-setuid, and the inner so we get the desired UID
      // within the container. We do this even if the image is a directory, to
      // reduce the number of code paths.
      namespaces_setup(c, geteuid(), 0, getegid(), 0);
#ifdef HAVE_LIBSQUASHFUSE
      if (c->type == IMG_SQUASH)
         sq_fork(c);
#endif
      namespaces_setup(c, 0, c->container_uid, 0, c->container_gid);
      mounts_setup(c);
      VERBOSE("prestart hooks: %d", list_count(c->hooks_prestart,
                                               sizeof(struct hook)));
      hooks_run(c, &c->hooks_prestart);
      pivot(c);
   } else
      namespaces_join(join.shared->winner_pid);
   if (c->join)
      join_end(c->join_ct);

}

/* Append hook function f to hook_list. When called, the hook will be passed
   d; this lets hooks receive arbitrary arguments (i.e., it’s a poor person’s
   closure). hook_list must be a member of c.

   “dup” says what to do if a hook with the same name is already in the list:

      HOOK_DUP_OK    add the hook anyway
      HOOK_DUP_SKIP  silently do nothing (i.e., don’t add the hook)
      HOOK_DUP_FAIL  fatal error  */
void hook_add(struct hook **hook_list, enum hook_dup dup,
              const char *name, hookf_t *f, void *d)
{
   // FIXME: hooks: environment variables, seccomp, CDI

   struct hook h;

   if (dup == HOOK_DUP_SKIP || dup == HOOK_DUP_FAIL) {
      bool dup_found = false;
      for (int i = 0; (*hook_list)[i].name != NULL; i++)
         if (!strcmp((*hook_list)[i].name, name)) {
            dup_found = true;
            break;
         }
      if (dup_found) {
         Te (dup == HOOK_DUP_SKIP, "invalid duplicate hook: %s", name);
         return;  // skip adding hook
      }
   }

   h.name = name;
   h.f = f;
   h.data = d;

   list_append((void **)hook_list, &h, sizeof(h));
}

/* Run hooks in hook_list, passing c, then set *hook_list to NULL. hook_list
   must be a member of c. */
void hooks_run(struct container *c, struct hook **hook_list)
{
   int hook_ct = list_count(*hook_list, sizeof((*hook_list)[0]));
   for (int i = 0; i < hook_ct; i++) {
      struct hook h = (*hook_list)[i];
      DEBUG("calling hook %d/%d: %s", i+1, hook_ct, h.name);
      h.f(c, h.data);
   }

   *hook_list = NULL;
}

/* Return image type of path, or exit with error if not a valid type. */
enum img_type image_type(const char *ref, const char *storage_dir)
{
   struct stat st;
   FILE *fp;
   char magic[4];  // four bytes, not a string

   // If there’s a directory in storage where we would expect there to be if
   // ref were an image name, assume it really is an image name.
   if (path_exists(img_name2path(ref, storage_dir), NULL, false))
      return IMG_NAME;

   // Now we know ref is a path of some kind, so find it.
   Zf (stat(ref, &st), "can't stat: %s", ref);

   // If ref is the path to a directory, then it’s a directory.
   if (S_ISDIR(st.st_mode))
      return IMG_DIRECTORY;

   // Now we know it’s file-like enough to read. See if it has the SquashFS
   // magic number.
   fp = fopen(ref, "rb");
   Tf (fp != NULL, "can't open: %s", ref);
   Tf (fread(magic, sizeof(char), 4, fp) == 4, "can't read: %s", ref);
   Zf (fclose(fp), "can't close: %s", ref);
   VERBOSE("image file magic expected: 6873 7173; actual: %x%x %x%x",
           magic[0], magic[1], magic[2], magic[3]);

   // If magic number matches, it’s a squash. Note: Magic number is 6873 7173,
   // i.e. “hsqs”. I think “sqsh” was intended but the superblock designers
   // were confused about endianness.
   // See: https://dr-emann.github.io/squashfs/
   if (memcmp(magic, "hsqs", 4) == 0)
      return IMG_SQUASH;

   // Well now we’re stumped.
   FATAL("unknown image type: %s", ref);
}

char *img_name2path(const char *name, const char *storage_dir)
{
   char *path;
   char *name_fs = ch_strdup(name);

   replace_char(name_fs, '/', '%');
   replace_char(name_fs, ':', '+');

   return path_join(storage_dir, path_join("img", name_fs));
}

/* Begin coordinated section of namespace joining. */
void join_begin(const char *join_tag)
{
   int fd;

   join.sem_name = cat("/ch-run_sem-", join_tag);
   join.shm_name = cat("/ch-run_shm-", join_tag);

   // Serialize.
   join.sem = sem_open(join.sem_name, O_CREAT, 0600, 1);
   T_ (join.sem != SEM_FAILED);
   sem_timedwait_relative(join.sem, JOIN_TIMEOUT);

   // Am I the winner?
   fd = shm_open(join.shm_name, O_CREAT|O_EXCL|O_RDWR, 0600);
   if (fd > 0) {
      VERBOSE("join: I won");
      join.winner_p = true;
      Z_ (ftruncate(fd, sizeof(*join.shared)));
   } else if (errno == EEXIST) {
      VERBOSE("join: I lost");
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

   // Winner keeps lock; losers parallelize (winner will be done by now).
   if (!join.winner_p)
      Z_ (sem_post(join.sem));
}

/* End coordinated section of namespace joining. */
void join_end(int join_ct)
{
   if (join.winner_p) {                                // winner still serial
      VERBOSE("join: winner initializing shared data");
      join.shared->winner_pid = getpid();
      join.shared->proc_left_ct = join_ct;
   } else                                              // losers serialize
      sem_timedwait_relative(join.sem, JOIN_TIMEOUT);

   join.shared->proc_left_ct--;
   VERBOSE("join: %d peers left excluding myself", join.shared->proc_left_ct);

   if (join.shared->proc_left_ct <= 0) {
      VERBOSE("join: cleaning up IPC resources");
      Te (join.shared->proc_left_ct == 0, "expected 0 peers left but found %d",
          join.shared->proc_left_ct);
      Zf (sem_unlink(join.sem_name), "can't unlink sem: %s", join.sem_name);
      Zf (shm_unlink(join.shm_name), "can't unlink shm: %s", join.shm_name);
   }

   Z_ (sem_post(join.sem));  // parallelize (all)

   Z_ (munmap(join.shared, sizeof(*join.shared)));
   Z_ (sem_close(join.sem));

   VERBOSE("join: done");
}

/* Set up the container filesystem tree. Namespaces must already be done. */
void mounts_setup(struct container *c)
{
   char *nr_parent, *mkdir_scratch;

   VERBOSE("creating container filesystem tree");
   LOG_IDS;
   mkdir_scratch = NULL;
   path_split(c->newroot, &nr_parent, NULL);

   // Claim new root for this namespace. Despite MS_REC in bind_mount(), we do
   // need both calls to avoid pivot_root(2) failing with EBUSY later.
   DEBUG("claiming new root for this namespace")
   bind_mount(c->newroot, c->newroot, BD_REQUIRED, "/", MS_PRIVATE, NULL);
   bind_mount(nr_parent, nr_parent, BD_REQUIRED, "/", MS_PRIVATE, NULL);
   // Re-mount new root read-only unless --write or already read-only.
   if (!c->writable && !(access(c->newroot, W_OK) == -1 && errno == EROFS)) {
      unsigned long flags =   path_mount_flags(c->newroot)
                            | MS_REMOUNT  // Re-mount ...
                            | MS_BIND     // only this mount point ...
                            | MS_RDONLY;  // read-only.
      Z_ (mount(NULL, c->newroot, NULL, flags, NULL));
   }
   // Overlay a tmpfs if --write-fake. See for useful details:
   // https://www.kernel.org/doc/html/v5.11/filesystems/tmpfs.html
   // https://www.kernel.org/doc/html/v5.11/filesystems/overlayfs.html
   if (c->overlay_size != NULL) {
      char *options;
      struct stat st;
      VERBOSE("overlaying tmpfs for --write-fake (%s)", c->overlay_size);
      options = cat("size=", c->overlay_size);
      Zf (mount(NULL, WF_MNT, "tmpfs", 0, options),
          "cannot mount tmpfs for overlay");
      Z_ (mkdir(WF_MNT "/upper", 0700));
      Z_ (mkdir(WF_MNT "/work", 0700));
      Z_ (mkdir(WF_MNT "/merged", 0700));
      mkdir_scratch = WF_MNT "/mkdir_overmount";
      Z_ (mkdir(mkdir_scratch, 0700));
      options = ch_asprintf(("lowerdir=%s,upperdir=%s,workdir=%s,"
                             "index=on,userxattr,volatile"),
                            c->newroot, WF_MNT "/upper", WF_MNT "/work"));
      // update newroot
      Zf (stat(c->newroot, &st),
          "can't stat new root; overmounted by tmpfs for -W?: %s", c->newroot);
      c->newroot = WF_MNT "/merged";
      Zf (mount(NULL, c->newroot, "overlay", 0, options),
          "can't overlay: %s, %s", c->newroot, options);
      VERBOSE("newroot updated: %s", c->newroot);
   }
   DEBUG("starting bind-mounts");
   // Bind-mount default files and directories.
   bind_mounts(BINDS_DEFAULT, c->newroot, MS_RDONLY, NULL);
   // /etc/passwd and /etc/group.
   if (!c->private_passwd)
      passwd_setup(c);
   // Container /tmp.
   if (c->private_tmp) {
      tmpfs_mount("/tmp", c->newroot, NULL);
   } else {
      bind_mount(host_tmp, "/tmp", BD_REQUIRED, c->newroot, 0, NULL);
   }
   // Bind-mount user’s home directory at /home/$USER if requested.
   if (c->host_home) {
      T_ (c->overlay_size != NULL);
      bind_mount(c->host_home, cat("/home/", username),
                 BD_MAKE_DST, c->newroot, 0, mkdir_scratch);
   }
   // Bind-mount user-specified directories.
   bind_mounts(c->binds, c->newroot, 0, mkdir_scratch);
}

/* Join a specific namespace. */
void namespace_join(pid_t pid, const char *ns)
{
   char *path;
   int fd;

   path = ch_asprintf(&path, "/proc/%d/ns/%s", pid, ns);
   fd = open(path, O_RDONLY);
   if (fd == -1) {
      if (errno == ENOENT) {
         Te (0, "join: no PID %d: %s not found", pid, path);
      } else {
         Tf (0, "join: can't open %s", path);
      }
   }
   /* setns(2) seems to be involved in some kind of race with syslog(3).
      Rarely, when configured with --enable-syslog, the call fails with
      EINVAL. We never figured out a proper fix, so just retry a few times in
      a loop. See issue #1270. */
   for (int i = 1; setns(fd, 0) != 0; i++)
      if (i >= 5) {
         Tf (0, "can’t join %s namespace of pid %d", ns, pid);
      } else {
         WARNING("can’t join %s namespace; trying again", ns);
         sleep(1);
      }
}

/* Join the existing namespaces containing process pid, which could be the
   join winner or another process. */
void namespaces_join(pid_t pid)
{
   VERBOSE("joining namespaces of pid %d", pid);
   namespace_join(pid, "user");
   namespace_join(pid, "mnt");
}

/* Activate the desired isolation namespaces. */
void namespaces_setup(const struct container *c, uid_t uid_out, uid_t uid_in,
                      gid_t gid_out, gid_t gid_in)
{
   int fd;

   VERBOSE("setting up namespaces: %d:%d -> %d:%d",
           uid_out, gid_out, uid_in, gid_in);
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
   T_ (1 <= dprintf(fd, "%d %d 1\n", uid_in, uid_out));
   Z_ (close(fd));
   LOG_IDS;

   T_ (-1 != (fd = open("/proc/self/setgroups", O_WRONLY)));
   T_ (1 <= dprintf(fd, "deny\n"));
   Z_ (close(fd));
   T_ (-1 != (fd = open("/proc/self/gid_map", O_WRONLY)));
   T_ (1 <= dprintf(fd, "%d %d 1\n", gid_in, gid_out));
   Z_ (close(fd));
   LOG_IDS;
}

/* Build /etc/passwd and /etc/group files and bind-mount them into newroot.

   /etc/passwd contains root, nobody, and an entry for the container UID,
   i.e., three entries, or two if the container UID is 0 or 65534. We copy the
   host's user data for the container UID, if that exists, and use dummy data
   otherwise (see issue #649). /etc/group works similarly: root, nogroup, and
   an entry for the container GID.

   We build new files to capture the relevant host username and group name
   mappings regardless of where they come from. We used to simply bind-mount
   the host's /etc/passwd and /etc/group, but this fails for LDAP at least;
   see issue #212. After bind-mounting, we remove the files from the host;
   they persist inside the container and then disappear completely when the
   container exits. */
void passwd_setup(const struct container *c)
{
   int fd;
   char *path;
   struct group *g;
   struct passwd *p;

   // /etc/passwd
   path = cat(host_tmp, "/ch-run_passwd.XXXXXX");
   T_ (-1 != (fd = mkstemp(path)));  // mkstemp(3) writes path
   if (c->container_uid != 0)
      T_ (1 <= dprintf(fd, "root:x:0:0:root:/root:/bin/sh\n"));
   if (c->container_uid != 65534)
      T_ (1 <= dprintf(fd, "nobody:x:65534:65534:nobody:/:/bin/false\n"));
   errno = 0;
   p = getpwuid(c->container_uid);
   if (p) {
      T_ (1 <= dprintf(fd, "%s:x:%u:%u:%s:/:/bin/sh\n", p->pw_name,
                       c->container_uid, c->container_gid, p->pw_gecos));
   } else {
      if (errno) {
         Tf (0, "getpwuid(3) failed");
      } else {
         VERBOSE("UID %d not found; using dummy info", c->container_uid);
         T_ (1 <= dprintf(fd, "%s:x:%u:%u:%s:/:/bin/sh\n", "charlie",
                          c->container_uid, c->container_gid, "Charlie"));
      }
   }
   Z_ (close(fd));
   bind_mount(path, "/etc/passwd", BD_REQUIRED, c->newroot, 0, NULL);
   Z_ (unlink(path));

   // /etc/group
   path = cat(host_tmp, "/ch-run_group.XXXXXX");
   T_ (-1 != (fd = mkstemp(path)));
   if (c->container_gid != 0)
      T_ (1 <= dprintf(fd, "root:x:0:\n"));
   if (c->container_gid != 65534)
      T_ (1 <= dprintf(fd, "nogroup:x:65534:\n"));
   errno = 0;
   g = getgrgid(c->container_gid);
   if (g) {
      T_ (1 <= dprintf(fd, "%s:x:%u:\n", g->gr_name, c->container_gid));
   } else {
      if (errno) {
         Tf (0, "getgrgid(3) failed");
      } else {
         VERBOSE("GID %d not found; using dummy info", c->container_gid);
         T_ (1 <= dprintf(fd, "%s:x:%u:\n", "charliegroup", c->container_gid));
      }
   }
   Z_ (close(fd));
   bind_mount(path, "/etc/group", BD_REQUIRED, c->newroot, 0, NULL);
   Z_ (unlink(path));
}

/* Pivot into the container. Note that pivot_root(2) requires a complex dance
   to work, i.e., to avoid multiple undocumented error conditions. This dance
   is explained in detail in bin/ch-checkns.c. */
void pivot(struct container *c)
{
   char *nr_parent, *nr_base;

   VERBOSE("pivoting into container");
   path_split(c->newroot, &nr_parent, &nr_base);

   // Overmount / to avoid EINVAL if it’s a rootfs.
   Z_ (chdir(nr_parent));
   Z_ (mount(nr_parent, "/", NULL, MS_MOVE, NULL));
   Z_ (chroot("."));
   // Pivot into the new root. Use /dev because it’s available even in
   // extremely minimal images.
   c->newroot = cat("/", nr_base);
   Zf (chdir(c->newroot), "can't chdir into new root");
   Zf (syscall(SYS_pivot_root, c->newroot, path_join(c->newroot, "dev")),
       "can't pivot_root(2)");
   Zf (chroot("."), "can't chroot(2) into new root");
   Zf (umount2("/dev", MNT_DETACH), "can't umount old root");
}

/* Replace the current process with user command and arguments. */
void run_user_command(char *argv[], const char *initial_dir)
{
   LOG_IDS;

   if (initial_dir != NULL)
      Zf (chdir(initial_dir), "can't cd to %s", initial_dir);

   VERBOSE("executing: %s", argv_to_string(argv));

   Zf (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0), "can't set no_new_privs");
   if (verbose < LL_INFO)
      T_ (freopen("/dev/null", "w", stdout));
   if (verbose < LL_STDERR)
      T_ (freopen("/dev/null", "w", stderr));
   ch_memory_log("usrx");
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

/* Mount a tmpfs at the given path. */
void tmpfs_mount(const char *dst, const char *newroot, const char *data)
{
   char *dst_full = cat(newroot, dst);

   Zf (mount(NULL, dst_full, "tmpfs", 0, data),
       "can't mount tmpfs at %s", dst_full);
}
