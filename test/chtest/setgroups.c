/* Try to drop the last supplemental group, and print a message to stdout
   describing what happened. */

#define _DEFAULT_SOURCE
#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

#define NGROUPS_MAX 128

int main()
{
   int group_ct;
   gid_t groups[NGROUPS_MAX];

   group_ct = getgroups(NGROUPS_MAX, groups);
   if (group_ct == -1) {
      printf("ERROR\tgetgroups(2) failed with errno=%d\n", errno);
      return 1;
   }

   fprintf(stderr, "found %d groups; trying to drop last group %d\n",
           group_ct, groups[group_ct - 1]);

   if (setgroups(group_ct - 1, groups)) {
      if (errno == EPERM) {
         printf("SAFE\tsetgroups(2) failed with EPERM\n");
         return 0;
      } else {
         printf("ERROR\tsetgroups(2) failed with errno=%d\n", errno);
         return 1;
      }
   } else {
      printf("RISK\tsetgroups(2) succeeded\n");
      return 1;
   }
}
