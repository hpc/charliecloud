/* Copyright © Los Alamos National Security, LLC, and others. */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

/* Print a formatted error message on stderr, then exit unsuccessfully. */
void fatal(char * fmt, ...)
{
   va_list ap;

   fprintf(stderr, "%s: ", program_invocation_short_name);
   va_start(ap, fmt);
   vfprintf(stderr, fmt, ap);
   va_end(ap);
   exit(EXIT_FAILURE);
}

/* Report the string expansion of errno on stderr, then exit unsuccessfully. */
void fatal_errno(char * file, int line)
{
   fatal("%s:%d: %d: %s\n", file, line, errno, strerror(errno));
}
