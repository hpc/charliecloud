/* This example program walks through the complete namespace / pivot_root(2)
   dance to enter a Charliecloud container, with each step documented. If you
   can compile it and run it without error as a normal user, ch-run will work
   too (if not, that's a bug). If not, this will hopefully help you understand
   more clearly what went wrong.

   pivot_root(2) has a large number of error conditions resulting in EINVAL
   that are not documented in the man page [1]. The ones we ran into are:

     1. The new root cannot be shared [2] outside the mount namespace. This
        makes sense, as we as an unprivileged user inside our namespace should
        not be able to change privileged things owned by other namespaces.

        This condition arises on systemd systems, which mount everything
        shared by default.

     2. The new root must not have been mounted before unshare(2), and/or it
        must be a mount point. The man page says "new_root does not have to be
        a mount point", but the source code comment says "[i]t must be a mount
        point" [3]. (I haven't isolated which was our problem.) In either
        case, this is a very common situation.

     3. The old root is a "rootfs" [4]. This is documented in a source code
        comment [3] but not the man page. This is an unusual situation for
        most contexts, because the rootfs is typically the initramfs
        overmounted during boot. However, some cluster provisioning systems,
        e.g. Perceus, use the original rootfs directly.

   Regarding overlayfs: It's very attractive to union-mount a tmpfs over the
   read-only image; then all programs can write to their hearts' desire, and
   the image does not change. This also simplifies the code. Unfortunately,
   overlayfs + userns is not allowed as of 4.4.23. See:
   https://lwn.net/Articles/671774/

   [1]: http://man7.org/linux/man-pages/man2/pivot_root.2.html
   [2]: https://www.kernel.org/doc/Documentation/filesystems/sharedsubtree.txt
   [3]: http://lxr.free-electrons.com/source/fs/namespace.c?v=4.4#L2952
   [4]: https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <sched.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "config.h"
#include "ch_misc.h"


const char usage[] = "\
\n\
Usage: ch-checkns\n\
\n\
Check \"ch-run\" prerequisites, e.g., namespaces and \"pivot_root(2)\".\n\
\n\
Example:\n\
\n\
  $ ch-checkns\n\
  ok\n";

#define TRY(x) if (x) fatal_(__FILE__, __LINE__, errno, #x)


void fatal_(const char *file, int line, int errno_, const char *str)
{
   char *url = "https://github.com/hpc/charliecloud/blob/master/bin/ch-checkns.c";
   printf("error: %s: %d: %s\n", file, line, str);
   printf("errno: %d\nsee: %s\n", errno_, url);
   exit(ERR_CHRUN);
}

int main(int argc, char *argv[])
{
   unsigned long flags;

   if (argc >= 2 && strcmp(argv[1], "--help") == 0) {
      fprintf(stderr, usage);
      return 0;
   }
   if (argc >= 2 && strcmp(argv[1], "--version") == 0) {
      version();
      return 0;
   }

   /* Ensure that our image directory exists. It doesn't really matter what's
      in it. */
   if (mkdir("/tmp/newroot", 0755) && errno != EEXIST)
      TRY (errno);

   /* Enter the mount and user namespaces. Note that in some cases (e.g., RHEL
      6.8), this will succeed even though the userns is not created. In that
      case, the following mount(2) will fail with EPERM. */
   TRY (unshare(CLONE_NEWNS|CLONE_NEWUSER));

   /* Claim the image for our namespace by recursively bind-mounting it over
      itself. This standard trick avoids conditions 1 and 2. */
   TRY (mount("/tmp/newroot", "/tmp/newroot", NULL,
              MS_REC | MS_BIND | MS_PRIVATE, NULL));

   /* The next few calls deal with condition 3. The solution is to overmount
      the root filesystem with literally anything else. We use the parent of
      the image, /tmp. This doesn't hurt if / is not a rootfs, so we always do
      it for simplicity. */

   /* Claim /tmp for our namespace. You would think that because /tmp contains
      /tmp/newroot and it's a recursive bind mount, we could claim both in the
      same call. But, this causes pivot_root(2) to fail later with EBUSY. */
   TRY (mount("/tmp", "/tmp", NULL, MS_REC | MS_BIND | MS_PRIVATE, NULL));

   /* chdir to /tmp. This moves the process' special "." pointer to
      the soon-to-be root filesystem. Otherwise, it will keep pointing to the
      overmounted root. See the e-mail at the end of:
      https://git.busybox.net/busybox/tree/util-linux/switch_root.c?h=1_24_2 */
   TRY (chdir("/tmp"));

   /* Move /tmp to /. (One could use this to directly enter the image,
      avoiding pivot_root(2) altogether. However, there are ways to remove all
      active references to the root filesystem. Then, the image could be
      unmounted, exposing the old root filesystem underneath. While
      Charliecloud does not claim a strong isolation boundary, we do want to
      make activating the UDSS irreversible.) */
   TRY (mount("/tmp", "/", NULL, MS_MOVE, NULL));

   /* Move the "/" special pointer to the new root filesystem, for the reasons
      above. (Similar reasoning applies for why we don't use chroot(2) to
      directly activate the UDSS.) */
   TRY (chroot("."));

   /* Make a place for the old (intermediate) root filesystem to land. */
   if (mkdir("/newroot/oldroot", 0755) && errno != EEXIST)
      TRY (errno);

   /* Re-mount the image read-only. */
   flags = path_mount_flags("/newroot") | MS_REMOUNT | MS_BIND | MS_RDONLY;
   TRY (mount(NULL, "/newroot", NULL, flags, NULL));

   /* Finally, make our "real" newroot into the root filesystem. */
   TRY (chdir("/newroot"));
   TRY (syscall(SYS_pivot_root, "/newroot", "/newroot/oldroot"));
   TRY (chroot("."));

   /* Unmount the old filesystem and it's gone for good. */
   TRY (umount2("/oldroot", MNT_DETACH));

   /* Report success. */
   printf("ok\n");
}
