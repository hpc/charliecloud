/* Copyright © Los Alamos National Security, LLC, and others. */

/* Test some result: if not zero, exit with an error. This is a macro so we
   have access to the file and line number. */
#define TRY(x) if (x) fatal_errno(NULL, __FILE__, __LINE__)
#define TRX(x, msg) if (x) fatal_errno(msg, __FILE__, __LINE__)

void fatal(char * fmt, ...);
void fatal_errno(char * msg, char * file, int line);
void version(void);
