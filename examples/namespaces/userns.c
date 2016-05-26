/* This is a simple hello-world implementation of user namespaces. */

#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

int main(void)
{
   uid_t euid = geteuid();
   int fd;

   printf("outside userns, uid=%d\n", euid);

   unshare(CLONE_NEWUSER);
   fd = open("/proc/self/uid_map", O_WRONLY);
   dprintf(fd, "0 %d 1\n", euid);
   close(fd);
   printf("in userns, uid=%d\n", geteuid());

   execlp("/bin/bash", "bash", NULL);
}
