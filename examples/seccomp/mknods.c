/* Use mknod(2) and mknodat(2) to create character and block devices (which
   should be blocked by the seccomp filters) and FIFOs (which should not.) */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

#define DEVNULL makedev(1,3)  // character device /dev/null
#define DEVRAM0 makedev(1,0)  // block device /dev/ram0
#define Z_(x)  if (x) (fprintf(stderr, "failed: %d: %s (%d)\n", \
                                       __LINE__, strerror(errno), errno), \
                       exit(1))

int main(void)
{
   Z_ (mknod("/_mknod_chr",  S_IFCHR, DEVNULL));
   Z_ (mknod("/_mknod_blk",  S_IFBLK, DEVRAM0));
   Z_ (mknod("/_mknod_fifo", S_IFIFO, 0));

   Z_ (mknodat(AT_FDCWD, "./_mknodat_chr", S_IFCHR, DEVNULL));
   Z_ (mknodat(AT_FDCWD, "./_mknodat_blk", S_IFBLK, DEVRAM0));
   Z_ (mknodat(AT_FDCWD, "./_mknodat_fifo", S_IFIFO, 0));
}
