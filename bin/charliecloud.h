/* Copyright © Los Alamos National Security, LLC, and others. */

/* Test some result: if not zero, exit with an error. This is a macro so we
   have access to the file and line number. */
#define TRY(x) if (x) fatal_errno(__FILE__, __LINE__)

void fatal(char * fmt, ...);
void fatal_errno(char * file, int line);

