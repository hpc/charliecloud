/* Copyright © Los Alamos National Security, LLC, and others. */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

#include "version.h"

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
void fatal_errno(char * msg, char * file, int line)
{
   if (msg == NULL)
      msg = "error";
   fatal("%s: %s (%s:%d:%d)\n", msg, strerror(errno), file, line, errno);
}

/* Report the version number. */
void version(void)
{
   fprintf(stderr, "%s\n", VERSION);
}
