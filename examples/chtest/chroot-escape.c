/* This program tries to escape a chroot using well-established methods, which
   are not an exploit but rather take advantage of chroot(2)'s well-defined
   behavior. We use device and inode numbers to test whether the root
   directory is the same before and after the escape.

   References:
     https://filippo.io/escaping-a-chroot-jail-slash-1/
     http://www.bpfh.net/simes/computing/chroot-break.html

*/

#define _DEFAULT_SOURCE
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
   printf("ERROR\t%s: %s\n", msg, strerror(errno));
   exit(EXIT_FAILURE);
}

int main()
{
   struct stat before, after;
   int fd;
   int status = EXIT_FAILURE;
   char tmpdir_template[] = "/tmp/chtest.tmp.chroot.XXXXXX";
   char * tmpdir_name;

   if (stat("/", &before)) fatal("stat before");

   tmpdir_name = mkdtemp(tmpdir_template);
   if (tmpdir_name == NULL)
      fatal("mkdtemp");

   if ((fd = open(".", O_RDONLY)) < 0) fatal("open");

   if (chroot(tmpdir_name)) {
      if (errno == EPERM) {
         printf("SAFE\tchroot(2) failed with EPERM\n");
         status = EXIT_SUCCESS;
      } else {
         fatal("chroot");
      }
   } else {
      if (fchdir(fd)) fatal("fchdir");
      if (close(fd)) fatal("close");

      for (int i = 0; i < 1024; i++)
         if (chdir("..")) fatal("chdir");

      /* If we got this far, we should be able to call chroot(2), so failure
         is an error. */
      if (chroot(".")) fatal("chroot");

      /* If root directory is the same before and after the attempted escape,
         then the escape failed, and we should be happy. */
      if (stat("/", &after)) fatal("stat after");
      if (before.st_dev == after.st_dev && before.st_ino == after.st_ino) {
         printf("SAFE\t");
         status = EXIT_SUCCESS;
      } else {
         printf("RISK\t");
         status = EXIT_FAILURE;
      }
      printf("dev/inode before %lu/%lu, after %lu/%lu\n",
             before.st_dev, before.st_ino, after.st_dev, after.st_ino);
   }

   if (rmdir(tmpdir_name)) fatal("rmdir");
   return status;
}
