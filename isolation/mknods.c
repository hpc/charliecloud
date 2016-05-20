/* Try to make some device files, and print a message to stdout describing
   what happened. See: https://www.kernel.org/doc/Documentation/devices.txt */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

const unsigned char_devs[] = { 1, 3,  /* /dev/null -- most innocuous */
                               1, 1,  /* /dev/mem -- most juicy */
                               0 };

int main(int argc, char ** argv)
{
   dev_t dev;
   char * dir;
   int i, j;
   unsigned maj, min;
   char * path;

   for (i = 1; i < argc; i++) {
      dir = argv[i];
      for (j = 0; char_devs[j] != 0; j += 2) {
         maj = char_devs[j];
         min = char_devs[j + 1];
         if (0 > asprintf(&path, "%s/c%d.%d", dir, maj, min)) {
            printf("ERROR\tasprintf() failed with errno=%d\n", errno);
            return 1;
         }
         fprintf(stderr, "trying to mknod %s\n", path);
         dev = makedev(maj, min);
         if (mknod(path, S_IFCHR | 0500, dev)) {
            // could not create device, make sure it's an error we expected
            switch (errno) {
            case EACCES:
            case EINVAL:   // e.g. /sys/firmware/efi/efivars
            case ENOENT:   // e.g. /proc
            case ENOTDIR:  // for bind-mounted files e.g. /etc/passwd
            case EPERM:
            case EROFS:
               break;
            default:
               printf("ERROR\tmknod(2) failed on %s with errno=%d\n",
                      path, errno);
               return 1;
            }
         } else {
            // created device OK, now try to remove it
            if (unlink(path)) {
               printf("ERROR\tmknod(2) succeeded on %s and then unlink(2) "
                      "failed with errno=%d", path, errno);
               return 1;
            }
            printf("RISK\tmknod(2) succeeded on %s (now removed)\n", path);
            return 1;
         }
      }
   }

   printf("SAFE\t%d devices in %d dirs failed\n",
          (i - 1) * (j / 2), i - 1);
   return 0;
}
