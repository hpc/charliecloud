/* Try to change effective UID. */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

#define NOBODY  65534
#define NOBODY2 65533

int main(int argc, char ** argv)
{
   // target UID is nobody, unless we're already nobody
   uid_t start = geteuid();
   uid_t target = start != NOBODY ? NOBODY : NOBODY2;
   int result;

   fprintf(stderr, "current EUID=%u, attempting EUID=%u\n", start, target);

   result = seteuid(target);

   // setuid(2) fails with EINVAL in user namespaces and EPERM if not root.
   if (result == 0) {
      printf("RISK\tsetuid(2) succeeded for EUID=%u\n", target);
      return 1;
   } else if (errno == EINVAL) {
      printf("SAFE\tsetuid(2) failed as expected with EINVAL\n");
      return 0;
   }

   printf("ERROR\tsetuid(2) failed unexpectedly with errno=%d\n", errno);
   return 1;
}
