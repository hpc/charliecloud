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
#include <dirent.h>
#include <sys/wait.h>

#include "config.h"
#include "ch_misc.h"
#include "ch_core.h"
#include "ops.h"
/** Macros **/

/* Timeout in seconds for waiting for join semaphore. */
#define JOIN_TIMEOUT 30

/* Maximum length of paths we're willing to deal with. (Note that
   system-defined PATH_MAX isn't reliable.) */
#define PATH_CHARS 4096


/** Constants **/

/* Default bind-mounts. */
struct bind BINDS_REQUIRED[] = {
   { "/dev",             "/dev" },
   { "/proc",            "/proc" },
   { "/sys",             "/sys" },
   { NULL, NULL }
};
struct bind BINDS_OPTIONAL[] = {
   { "/etc/hosts",               "/etc/hosts" },
   { "/etc/resolv.conf",         "/etc/resolv.conf" },
   { "/var/opt/cray/alps/spool", "/var/opt/cray/alps/spool" },
   { "/var/lib/hugetlbfs",       "/var/opt/cray/hugetlbfs" },
   { NULL, NULL }
};


/** Global variables **/
struct squash *s;
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


/** Function prototypes (private) **/

void bind_mount(const char *src, const char *dst, const char *newroot,
                enum bind_dep dep, unsigned long flags);
void bind_mounts(const struct bind *binds, const char *newroot,
                 enum bind_dep dep, unsigned long flags);
void enter_udss(struct container *c);
void join_begin(int join_ct, const char *join_tag);
void join_namespace(pid_t pid, const char *ns);
void join_namespaces(pid_t pid);
void join_end();
void sem_timedwait_relative(sem_t *sem, int timeout);
void setup_namespaces(const struct container *c);
void setup_passwd(const struct container *c);
void tmpfs_mount(const char *dst, const char *newroot, const char *data);


/** Functions **/

/* Bind-mount the given path into the container image. */
void bind_mount(const char *src, const char *dst, const char *newroot,
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
void bind_mounts(const struct bind *binds, const char *newroot,
                 enum bind_dep dep, unsigned long flags)
{
   for (int i = 0; binds[i].src != NULL; i++)
      bind_mount(binds[i].src, binds[i].dst, newroot, dep, flags);
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
   in bin/ch-checkns.c. */
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
void join_begin(int join_ct, const char *join_tag)
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
   Zf (setns(fd, 0), "can't join %s namespace of pid %d", ns, pid);
}

/* Join the existing namespaces created by the join winner. */
void join_namespaces(pid_t pid)
{
   INFO("joining namespaces of pid %d", pid);
   join_namespace(pid, "user");
   join_namespace(pid, "mnt");
}

/** exit handler ensures that any filesystems are unmounted in 
 * the event of system exit */
void kill_fuse_loop()
{  
   if(s->fuse){
      fuse_exit(s->fuse);
      fuse_unmount(s->mountdir, s->ch);
      fuse_destroy(s->fuse);
      rmdir(s->mountdir);
   }
}
	
/* Replace the current process with user command and arguments. */
void run_user_command(char *argv[], const char *initial_dir)
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
   if(s->fuse){
      int status;
      if(fork() == 0){
         execvp(argv[0], argv);
         Tf (0, "can't execve(2): %s", argv[0]);
      }
      wait(&status);
      kill(s->pid,SIGINT);
   } else {	
      execvp(argv[0], argv);  // only returns if error
      Tf (0, "can't execve(2): %s", argv[0]);
   }
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
void setup_namespaces(const struct container *c)
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
   T_ (path = strdup("/tmp/ch-run_passwd.XXXXXX"));
   T_ (-1 != (fd = mkstemp(path)));  // mkstemp(3) writes path
   if (c->container_uid != 0)
      T_ (1 <= dprintf(fd, "root:x:0:0:root:/root:/bin/sh\n"));
   if (c->container_uid != 65534)
      T_ (1 <= dprintf(fd, "nobody:x:65534:65534:nobody:/:/bin/false\n"));
   errno = 0;
   p = getpwuid(c->container_uid);
   if (p) {
      T_ (1 <= dprintf(fd, "%s:x:%u:%u:%s:/home/%s:/bin/sh\n",
                       p->pw_name, c->container_uid, c->container_gid,
                       p->pw_gecos, getenv("USER")));
   } else {
      if (errno) {
         Tf (0, "getpwuid(3) failed");
      } else {
         INFO("UID %d not found; using dummy info", c->container_uid);
         T_ (1 <= dprintf(fd, "%s:x:%u:%u:%s:/home/%s:/bin/sh\n",
                          "charlie", c->container_uid, c->container_gid,
                          "Charliecloud User", "charlie"));
      }
   }
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
   errno = 0;
   g = getgrgid(c->container_gid);
   if (g) {
      T_ (1 <= dprintf(fd, "%s:x:%u:\n", g->gr_name, c->container_gid));
   } else {
      if (errno) {
         Tf (0, "getgrgid(3) failed");
      } else {
         INFO("GID %d not found; using dummy info", c->container_gid);
         T_ (1 <= dprintf(fd, "%s:x:%u:\n", "charliegroup", c->container_gid));
      }
   }
   Z_ (close(fd));
   bind_mount(path, "/etc/group", c->newroot, BD_REQUIRED, 0);
   Z_ (unlink(path));
}

/* Mount a tmpfs at the given path. */
void tmpfs_mount(const char *dst, const char *newroot, const char *data)
{
   char *dst_full = cat(newroot, dst);

   Zf (mount(NULL, dst_full, "tmpfs", 0, data),
       "can't mount tmpfs at %s", dst_full);
}

/* mounts a squash file system and starts child process
 * to handle all file system operations*/
int squashmount(struct squash *s)
{
   struct fuse_args args = FUSE_ARGS_INIT(0, NULL);
   args.allocated = 1;
   sqfs_hl *hl;
   int ret;
   fuse_operations sqfs_hl_ops;
   get_fuse_ops(&sqfs_hl_ops);
   hl =sqfs_hl_open(s->filepath, 0);
   Te(hl, "squashfs %s does not exist at this location", s->filepath);
   Ze(opendir(s->mountdir), "%s, Directory already exists",s->mountdir);
   Ze(mkdir(s->mountdir,0777), "%s, failed to create directory", s->mountdir);
   fuse_opt_add_arg(&args, "");
   s->ch = fuse_mount(s->mountdir,&args);
   Te(s->ch, "unable to mount at %s", s->mountdir);
   s->fuse = fuse_new(s->ch,&args, &sqfs_hl_ops, sizeof(sqfs_hl_ops), hl);
   Ze((s->fuse==NULL), "failed to create fuse session");
   Ze(0>fuse_set_signal_handlers(fuse_get_session(s->fuse)), "failed to set up signal handlers");
   signal(SIGINT, kill_fuse_loop);
   if((s->pid = fork()) == 0){
      ret = fuse_loop(s->fuse);
      exit(0);
   } else{
      return ret;
   }
} 
