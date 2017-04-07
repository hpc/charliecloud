/* Copyright © Los Alamos National Security, LLC, and others. */

/* Test some result: if not zero, exit with an error. This is a macro so we
   have access to the file and line number.

   Note: This macro is sometimes used for things other than system calls. If
   errno is not set when the program aborts, the resulting error message will
   say "error: Success", which is very confusing. Thus, make sure that users
   won't see those. */
#define TRY(x) if (x) fatal_errno(NULL, __FILE__, __LINE__)
#define TRX(x, msg) if (x) fatal_errno(msg, __FILE__, __LINE__)

void fatal(char * fmt, ...);
void fatal_errno(char * msg, char * file, int line);
void version(void);
