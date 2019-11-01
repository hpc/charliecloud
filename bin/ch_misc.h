/* Copyright © Triad National Security, LLC, and others.

   This interface contains miscellaneous utility features. It is separate so
   that peripheral Charliecloud C programs don't have to link in the extra
   libraries that ch_core requires. */

#define _GNU_SOURCE
#include <errno.h>
#include <stdbool.h>


/** Macros **/

/* Log the current UIDs. */
#define LOG_IDS log_ids(__func__, __LINE__)

/* Test some value, and if it's not what we expect, exit with an error. These
   are macros so we have access to the file and line number.

                     verify x is true (non-zero); otherwise print then exit:
     T_ (x)            default error message including file, line, errno
     Tf (x, fmt, ...)  printf-style message followed by file, line, errno
     Te (x, fmt, ...)  same without errno

                     verify x is zero (false); otherwise print as above & exit
     Z_ (x)
     Zf (x, fmt, ...)
     Ze (x, fmt, ...)

   errno is omitted if it's zero.

   Examples:

     Z_ (chdir("/does/not/exist"));
       -> ch-run: error: No such file or directory (ch-run.c:138 2)
     Zf (chdir("/does/not/exist"), "foo");
       -> ch-run: foo: No such file or directory (ch-run.c:138 2)
     Ze (chdir("/does/not/exist"), "foo");
       -> ch-run: foo (ch-run.c:138)
     errno = 0;
     Zf (0, "foo");
       -> ch-run: foo (ch-run.c:138)

   Typically, Z_ and Zf are used to check system and standard library calls,
   while T_ and Tf are used to assert developer-specified conditions.

   errno is not altered by these macros unless they exit the program.

   FIXME: It would be nice if we could collapse these to fewer macros.
   However, when looking into that I ended up in preprocessor black magic
   (e.g. https://stackoverflow.com/a/2308651) that I didn't understand. */
#define T_(x)      if (!(x)) msg(0, __FILE__, __LINE__, errno, NULL)
#define Tf(x, ...) if (!(x)) msg(0, __FILE__, __LINE__, errno, __VA_ARGS__)
#define Te(x, ...) if (!(x)) msg(0, __FILE__, __LINE__, 0, __VA_ARGS__)
#define Z_(x)      if (x)    msg(0, __FILE__, __LINE__, errno, NULL)
#define Zf(x, ...) if (x)    msg(0, __FILE__, __LINE__, errno, __VA_ARGS__)
#define Ze(x, ...) if (x)    msg(0, __FILE__, __LINE__, 0, __VA_ARGS__)

#define FATAL(...)   msg(0, __FILE__, __LINE__, 0, __VA_ARGS__);
#define WARNING(...) msg(1, __FILE__, __LINE__, 0, __VA_ARGS__);
#define INFO(...)    msg(2, __FILE__, __LINE__, 0, __VA_ARGS__);
#define DEBUG(...)   msg(3, __FILE__, __LINE__, 0, __VA_ARGS__);


/** External variables **/

extern int verbose;

/** Function prototypes **/

char *cat(char *a, char *b);
void log_ids(const char *func, int line);
void msg(int level, char *file, int line, int errno_, char *fmt, ...);
bool path_exists(char *path);
unsigned long path_mount_flags(char *path);
void path_split(char *path, char **dir, char **base);
void split(char **a, char **b, char *str, char del);
void version(void);
