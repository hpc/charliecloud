/* This program prints the effective user ID on stdout and exits. It is useful
   for testing whether the setuid bit was effective. */

#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

int main(void)
{
   printf("%u\n", geteuid());
   return 0;
}
