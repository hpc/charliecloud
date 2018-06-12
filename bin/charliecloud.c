/* Copyright © Los Alamos National Security, LLC, and others. */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "version.h"

/* Level of chatter on stderr desired (0-3). */
int verbose;

/* Names of verbosity levels. */
const char * verbose_levels[] = { "error", "warning", "info", "debug" };


/* Print a formatted message on stderr if the level warrants it. Levels:

     0 : "error"   : always print; exit unsuccessfully afterwards
     1 : "warning" : always print
     1 : "info"    : print if verbose >= 2
     2 : "debug"   : print if verbose >= 3 */
void msg(int level, char * file, int line, int errno_, char * fmt, ...)
{
   va_list ap;

   if (level > verbose)
      return;

   fprintf(stderr, "%s[%d]: ", program_invocation_short_name, getpid());

   if (fmt == NULL)
      fputs(verbose_levels[level], stderr);
   else {
      va_start(ap, fmt);
      vfprintf(stderr, fmt, ap);
      va_end(ap);
   }

   if (errno_)
      fprintf(stderr, ": %s (%s:%d %d)\n",
              strerror(errno_), file, line, errno_);
   else
      fprintf(stderr, " (%s:%d)\n", file, line);

   if (level == 0)
      exit(EXIT_FAILURE);
}

/* Report the version number. */
void version(void)
{
   fprintf(stderr, "%s\n", VERSION);
}
