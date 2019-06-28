/* Copyright © Los Alamos National Security, LLC, and others. */

#define _GNU_SOURCE
#include <stdbool.h>

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


/** Types **/

struct bind {
   char *src;
   char *dst;
};

enum bind_dep {
   BD_REQUIRED,  // both source and destination must exist
   BD_OPTIONAL   // if either source or destination missing, do nothing
};

struct container {
   struct bind *binds;
   bool ch_ssh;         // bind /usr/bin/ch-ssh?
   gid_t container_gid;
   uid_t container_uid;
   char *newroot;
   bool join;           // is this a synchronized join?
   int join_ct;         // number of peers in a synchronized join
   pid_t join_pid;      // process in existing namespace to join
   char *join_tag;      // identifier for synchronized join
   bool private_home;   // don't bind user home directory
   bool private_passwd; // don't bind custom /etc/{passwd,group}
   bool private_tmp;    // don't bind host's /tmp
   char *old_home;      // host path to user's home directory (i.e. $HOME)
   bool writable;
};


/** External variables from charliecloud.c **/

extern int verbose;


/** Function prototypes from charliecloud.c **/

void containerize(struct container *c);
void msg(int level, char *file, int line, int errno_, char *fmt, ...);
void run_user_command(char *argv[], char *initial_dir);
void split(char **a, char **b, char *str, char del);
void version(void);
