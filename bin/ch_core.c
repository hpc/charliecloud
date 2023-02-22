/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <fcntl.h>
#include <grp.h>
#include <libgen.h>
#include <pwd.h>
#include <sched.h>
#include <semaphore.h>
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

#include "config.h"
#include "ch_misc.h"
#include "ch_core.h"
#ifdef HAVE_LIBSQUASHFUSE
#include "ch_fuse.h"
#endif


/** Macros **/

/* Timeout in seconds for waiting for join semaphore. */
#define JOIN_TIMEOUT 30

/* Maximum length of paths we're willing to deal with. (Note that
   system-defined PATH_MAX isn't reliable.) */
#define PATH_CHARS 4096


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
                const char *newroot, unsigned long flags);
void bind_mounts(const struct bind *binds, const char *newroot,
                 unsigned long flags);
void enter_udss(struct container *c);
void join_begin(const char *join_tag);
void join_namespace(pid_t pid, const char *ns);
void join_namespaces(pid_t pid);
void join_end(int join_ct);
void sem_timedwait_relative(sem_t *sem, int timeout);
void setup_namespaces(const struct container *c, uid_t uid_out, uid_t uid_in,
                      gid_t gid_out, gid_t gid_in);
void setup_passwd(const struct container *c);
void tmpfs_mount(const char *dst, const char *newroot, const char *data);


/** Functions **/

/* Bind-mount the given path into the container image. */
void bind_mount(const char *src, const char *dst, enum bind_dep dep,
                const char *newroot, unsigned long flags)
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
         mkdirs(newroot, dst, bind_mount_paths);
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
                 unsigned long flags)
{
   for (int i = 0; binds[i].src != NULL; i++)
      bind_mount(binds[i].src, binds[i].dst, binds[i].dep, newroot, flags);
}

/* Set up new namespaces or join existing namespaces. */
void containerize(struct container *c)
{
   if (c->join_pid) {
      join_namespaces(c->join_pid);
      return;
   }
   if (c->join)
      join_begin(c->join_tag);
   if (!c->join || join.winner_p) {
      // Set up two nested user+mount namespaces: the outer so we can run
      // fusermount3 non-setuid, and the inner so we get the desired UID
      // within the container. We do this even if the image is a directory, to
      // reduce the number of code paths.
      setup_namespaces(c, geteuid(), 0, getegid(), 0);
#ifdef HAVE_LIBSQUASHFUSE
      if (c->type == IMG_SQUASH)
         sq_fork(c);
#endif
      setup_namespaces(c, 0, c->container_uid, 0, c->container_gid);
      enter_udss(c);
   } else
      join_namespaces(join.shared->winner_pid);
   if (c->join)
      join_end(c->join_ct);

}

/* Enter the UDSS. After this, we are inside the UDSS.

   Note that pivot_root(2) requires a complex dance to work, i.e., to avoid
   multiple undocumented error conditions. This dance is explained in detail
   in bin/ch-checkns.c. */
void enter_udss(struct container *c)
{
   char *newroot_parent, *newroot_base;

   LOG_IDS;

   path_split(c->newroot, &newroot_parent, &newroot_base);

   // Claim new root for this namespace. We do need both calls to avoid
   // pivot_root(2) failing with EBUSY later.
   bind_mount(c->newroot, c->newroot, BD_REQUIRED, "/", MS_PRIVATE);
   bind_mount(newroot_parent, newroot_parent, BD_REQUIRED, "/", MS_PRIVATE);
   // Bind-mount default files and directories.
   bind_mounts(BINDS_DEFAULT, c->newroot, MS_RDONLY);
   // /etc/passwd and /etc/group.
   if (!c->private_passwd)
      setup_passwd(c);
   // Container /tmp.
   if (c->private_tmp) {
      tmpfs_mount("/tmp", c->newroot, NULL);
   } else {
      bind_mount(host_tmp, "/tmp", BD_REQUIRED, c->newroot, 0);
   }
   // Container /home.
   if (c->host_home) {
      char *newhome;
      // Mount tmpfs on guest /home because guest root may be read-only.
      tmpfs_mount("/home", c->newroot, "size=4m");
      // Bind-mount user's home directory at /home/$USER.
      newhome = cat("/home/", username);
      Z_ (mkdir(cat(c->newroot, newhome), 0755));
      bind_mount(c->host_home, newhome, BD_REQUIRED, c->newroot, 0);
   }
   // Container /usr/bin/ch-ssh.
   if (c->ch_ssh) {
      char chrun_file[PATH_CHARS];
      int len = readlink("/proc/self/exe", chrun_file, PATH_CHARS);
      T_ (len >= 0);
      Te (path_exists(cat(c->newroot, "/usr/bin/ch-ssh"), NULL, true),
          "--ch-ssh: /usr/bin/ch-ssh not in image");
      chrun_file[ len<PATH_CHARS ? len : PATH_CHARS-1 ] = 0; // terminate; #315
      bind_mount(cat(dirname(chrun_file), "/ch-ssh"), "/usr/bin/ch-ssh",
                 BD_REQUIRED, c->newroot, 0);
   }

   // Re-mount new root read-only unless --write or already read-only.
   if (!c->writable && !(access(c->newroot, W_OK) == -1 && errno == EROFS)) {
      unsigned long flags =   path_mount_flags(c->newroot)
                            | MS_REMOUNT  // Re-mount ...
                            | MS_BIND     // only this mount point ...
                            | MS_RDONLY;  // read-only.
      Zf (mount(NULL, c->newroot, NULL, flags, NULL),
          "can't re-mount image read-only (is it on NFS?)");
   }
   // Bind-mount user-specified directories.
   bind_mounts(c->binds, c->newroot, 0);
   // Overmount / to avoid EINVAL if it's a rootfs.
   Z_ (chdir(newroot_parent));
   Z_ (mount(newroot_parent, "/", NULL, MS_MOVE, NULL));
   Z_ (chroot("."));
   c->newroot = cat("/", newroot_base);
   // Pivot into the new root. Use /dev because it's available even in
   // extremely minimal images.
   Zf (chdir(c->newroot), "can't chdir into new root");
   Zf (syscall(SYS_pivot_root, c->newroot, cat(c->newroot, "/dev")),
       "can't pivot_root(2)");
   Zf (chroot("."), "can't chroot(2) into new root");
   Zf (umount2("/dev", MNT_DETACH), "can't umount old root");
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
   char *name_fs = strdup(name);

   replace_char(name_fs, '/', '%');
   replace_char(name_fs, ':', '+');

   T_ (1 <= asprintf(&path, "%s/img/%s", storage_dir, name_fs));

   free(name_fs);  // make Tim happy
   return path;
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

/* Join a specific namespace. */
void join_namespace(pid_t pid, const char *ns)
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

/* Join the existing namespaces created by the join winner. */
void join_namespaces(pid_t pid)
{
   VERBOSE("joining namespaces of pid %d", pid);
   join_namespace(pid, "user");
   join_namespace(pid, "mnt");
}

/* Replace the current process with user command and arguments. */
void run_user_command(char *argv[], const char *initial_dir)
{
   LOG_IDS;

   if (initial_dir != NULL)
      Zf (chdir(initial_dir), "can't cd to %s", initial_dir);

   VERBOSE("executing: %s", argv_to_string(argv));

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
void setup_namespaces(const struct container *c, uid_t uid_out, uid_t uid_in,
                      gid_t gid_out, gid_t gid_in)
{
   int fd;

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
void setup_passwd(const struct container *c)
{
   int fd;
   char *path;
   struct group *g;
   struct passwd *p;

   // /etc/passwd
   T_ (path = cat(host_tmp, "/ch-run_passwd.XXXXXX"));
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
   bind_mount(path, "/etc/passwd", BD_REQUIRED, c->newroot, 0);
   Z_ (unlink(path));

   // /etc/group
   T_ (path = cat(host_tmp, "/ch-run_group.XXXXXX"));
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
   bind_mount(path, "/etc/group", BD_REQUIRED, c->newroot, 0);
   Z_ (unlink(path));
}

/* Mount a tmpfs at the given path. */
void tmpfs_mount(const char *dst, const char *newroot, const char *data)
{
   char *dst_full = cat(newroot, dst);

   Zf (mount(NULL, dst_full, "tmpfs", 0, data),
       "can't mount tmpfs at %s", dst_full);
}
