/* Copyright © Los Alamos National Security, LLC, and others. */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include "version.h"


/* Print a formatted error message on stderr, followed by the string expansion
   of errno, source file, line number, errno, and newline; then exit
   unsuccessfully. If errno is zero, then don't include it, because then it
   says "success", which is super confusing in an error message. */
void fatal(char * file, int line, int errno_, char * fmt, ...)
{
   va_list ap;

   fputs(program_invocation_short_name, stderr);
   fputs(": ", stderr);

   if (fmt == NULL)
      fputs("error", stderr);
   else {
      va_start(ap, fmt);
      vfprintf(stderr, fmt, ap);
      va_end(ap);
   }

   if (errno)
      fprintf(stderr, ": %s (%s:%d %d)\n", strerror(errno), file, line, errno);
   else
      fprintf(stderr, " (%s:%d)\n", file, line);
   exit(EXIT_FAILURE);
}

/* Report the version number. */
void version(void)
{
   fprintf(stderr, "%s\n", VERSION);
}
