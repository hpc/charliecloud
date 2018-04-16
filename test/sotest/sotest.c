#include <stdio.h>
#include <stdlib.h>

int increment(int a);

int main()
{
   int b = 8675308;
   printf("libsotest says %d incremented is %d\n", b, increment(b));
   exit(0);
}
