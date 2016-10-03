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

   Notes on overlayfs:

     1. Ideally, we would re-mount the lower directory read-only, to protect
        it against changes resulting from bugs. However, this raises a corner
        case: if the lower directory crosses filesystems, then only the top
        filesystem will become read-only, because MS_REMOUNT cannot be applied
        recursively. Thus, in order to avoid rare bugs, we don't re-mount
        read-only. This simplifies the code as well.

   [1]: http://man7.org/linux/man-pages/man2/pivot_root.2.html
   [2]: https://www.kernel.org/doc/Documentation/filesystems/sharedsubtree.txt
   [3]: http://lxr.free-electrons.com/source/fs/namespace.c?v=4.4#L2952
   [4]: https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <sched.h>
#include <stdlib.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define TRY(x) if (x) fatal_errno(__LINE__)

void fatal_errno(int line)
{
   printf("error at line %d, errno=%d\n", line, errno);
   exit(1);
}

int main(void)
{
   /* Ensure that our image directory exists. It doesn't really matter what's
      in it. */
   if (mkdir("/tmp/newroot", 0755) && errno != EEXIST)
      TRY (errno);

   /* Enter the mount and user namespaces. Note that in some cases (e.g., RHEL
      6.8), this will succeed even though the userns is not created. In that
      case, the following mount(2) will fail with EPERM. */
   TRY (unshare(CLONE_NEWNS|CLONE_NEWUSER));

   /* Create a tmpfs to hold any image changes the container wants to make
      (these will be discarded), and place it on top of the image using
      overlayfs. This also helps us be tidier about all these root directories
      flying around. (Note that it doesn't really matter where we mount it,
      since only our namespace can see it.) */
   TRY (mount(NULL, "/mnt", "tmpfs", 0, "size=16m"));
   TRY (mkdir("/mnt/upper", 0755));
   TRY (mkdir("/mnt/lower", 0755));
   TRY (mkdir("/mnt/work", 0755));
   TRY (mkdir("/mnt/merged", 0755));

   /* Claim the image for our namespace by recursively bind-mounting it. This
      avoids conditions 1 and 2. (While we put it on /mnt/lower, the standard
      trick is to bind-mount it over itself.) */
   TRY (mount("/tmp/newroot", "/mnt/lower", NULL,
              MS_REC | MS_BIND | MS_PRIVATE, NULL));

   /* Activate the overlay. */
   TRY (mount(NULL, "/mnt/merged", "overlay", 0,
              "lowerdir=/mnt/lower,upperdir=/mnt/upper,workdir=/mnt/work"));

   /* The next few calls deal with condition 3. The solution is to overmount
      the root filesystem with literally anything else. We use /mnt. This
      doesn't hurt if / is not a rootfs, so we always do it for simplicity. */

   /* chdir to /mnt. This moves the process' special "." pointer to
      the soon-to-be root filesystem. Otherwise, it will keep pointing to the
      overmounted root. See the e-mail at the end of:
      https://git.busybox.net/busybox/tree/util-linux/switch_root.c?h=1_24_2 */
   TRY (chdir("/mnt"));

   /* Move /mnt to /. (One could use this to directly enter the image,
      avoiding pivot_root(2) altogether. However, there are ways to remove all
      active references to the root filesystem. Then, the image could be
      unmounted, exposing the old root filesystem underneath. While
      Charliecloud does not claim a strong isolation boundary, we do want to
      make activating the UDSS irreversible.) */
   TRY (mount("/mnt", "/", NULL, MS_MOVE, NULL));

   /* Move the "/" special pointer to the new root filesystem, similar to
      above. (Similar reasoning applies for why we don't use chroot(2) to
      directly activate the UDSS.) */
   TRY (chroot("."));

   /* Make a place for the old (intermediate) root filesystem to land.

      Note also that you can use this to prove that we did not write to the
      image -- this new directory will not exist after the program exits. */
   if (mkdir("/merged/oldroot", 0755) && errno != EEXIST)
      TRY (errno);

   /* Finally, make our "real" newroot into the root filesystem. */
   TRY (chdir("/merged"));
   TRY (syscall(SYS_pivot_root, "/merged", "/merged/oldroot"));
   TRY (chroot("."));

   /* Unmount the old filesystem and it's gone for good. */
   TRY (umount2("/oldroot", MNT_DETACH));

   /* Report success. */
   printf("ok\n");
}
