/* This program tries to escape a chroot using well-established methods, which
   are not an exploit but rather take advantage of chroot(2)'s well-defined
   behavior. We use device and inode numbers to test whether the root
   directory is the same before and after the escape.

   If escape succeeded or there was an unexpected error, print "FAIL" and exit
   with EXIT_FAILURE; if not (re-chroot(2) returned with EPERM or had no
   effect), print "OK" and exit with EXIT_SUCCESS.

   For example, using the chroot(1) utility and compiling statically so the
   binary can be used a la carte:

     $ gcc -static chroot-escape.c
     $ ./a.out
     OK chroot(2) failed with EPERM
     $ sudo ./a.out
     OK dev/inode before 2304/2, after 2304/2
     $ sudo chroot . ./a.out
     FAIL dev/inode before 2304/59645296, after 2304/2
     $ sudo chroot --userspec $(id -u):$(id -g) /tmp ./chroot-escape
     OK chroot(2) failed with EPERM
     $ rmdir chroot-escape-tmp*

   Reference:
     https://filippo.io/escaping-a-chroot-jail-slash-1/
     http://www.bpfh.net/simes/computing/chroot-break.html

*/

#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <string.h>
#include <unistd.h>


void fatal(char * msg)
{
   perror(msg);
   exit(EXIT_FAILURE);
}

int main()
{
   struct stat before, after;
   int fd, status;
   char tmpdir_template[] = "./chroot-escape-tmp-XXXXXX"; // not cleaned up
   char * tmpdir_name;

   if (stat("/", &before)) fatal("stat before");

   tmpdir_name = mkdtemp(tmpdir_template);
   if (tmpdir_name == NULL)
      fatal("mkdtemp");

   if ((fd = open(".", O_RDONLY)) < 0) fatal("open");

   if (chroot(tmpdir_name)) {
      if (errno == EPERM) {
         printf("OK chroot(2) failed with EPERM\n");
         return EXIT_SUCCESS;
      } else {
         printf("FAIL chroot(2) failed with errno %d: %s\n",
                errno, strerror(errno));
         return EXIT_FAILURE;
      }
   }

   if (fchdir(fd)) fatal("fchdir");
   if (close(fd)) fatal("close");

   for (int i = 0; i < 1024; i++)
      if (chdir("..")) fatal("chdir");

   /* If we got this far, we should be able to call chroot(2), so any error is
      a FAIL. */
   if (chroot(".")) fatal("chroot");

   /* If root directory is the same before and after the attempted escape,
      then the escape failed, and we should be happy. */
   if (stat("/", &after)) fatal("stat after");
   if (before.st_dev == after.st_dev && before.st_ino == after.st_ino) {
      printf("OK ");
      status = EXIT_SUCCESS;
   } else {
      printf("FAIL ");
      status = EXIT_FAILURE;
   }
   printf("dev/inode before %lu/%lu, after %lu/%lu\n",
          before.st_dev, before.st_ino, after.st_dev, after.st_ino);

   return status;
}
