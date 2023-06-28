/* Copyright © Triad National Security, LLC, and others.

   This interface contains miscellaneous utility features. It is separate so
   that peripheral Charliecloud C programs don't have to link in the extra
   libraries that ch_core requires. */

#define _GNU_SOURCE
#include <errno.h>
#include <sys/stat.h>
#include <stdbool.h>


/** Macros **/

/* Log the current UIDs. */
#define LOG_IDS log_ids(__func__, __LINE__)

/* C99 does not have noreturn or _Noreturn (those are C11), but GCC, Clang,
   and hopefully others support the following extension. */
#define noreturn __attribute__ ((noreturn))

/* Test some value, and if it's not what we expect, exit with a fatal error.
   These are macros so we have access to the file and line number.

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
#define T_(x)      if (!(x)) msg_fatal(__FILE__, __LINE__, errno, NULL)
#define Tf(x, ...) if (!(x)) msg_fatal(__FILE__, __LINE__, errno, __VA_ARGS__)
#define Te(x, ...) if (!(x)) msg_fatal(__FILE__, __LINE__, 0, __VA_ARGS__)
#define Z_(x)      if (x)    msg_fatal(__FILE__, __LINE__, errno, NULL)
#define Zf(x, ...) if (x)    msg_fatal(__FILE__, __LINE__, errno, __VA_ARGS__)
#define Ze(x, ...) if (x)    msg_fatal(__FILE__, __LINE__, 0, __VA_ARGS__)

#define FATAL(...)   msg_fatal(      __FILE__, __LINE__, 0, __VA_ARGS__);
#define WARNING(...) msg(LL_WARNING, __FILE__, __LINE__, 0, __VA_ARGS__);
#define INFO(...)    msg(LL_INFO,    __FILE__, __LINE__, 0, __VA_ARGS__);
#define VERBOSE(...) msg(LL_VERBOSE, __FILE__, __LINE__, 0, __VA_ARGS__);
#define DEBUG(...)   msg(LL_DEBUG,   __FILE__, __LINE__, 0, __VA_ARGS__);
#define TRACE(...)   msg(LL_TRACE,   __FILE__, __LINE__, 0, __VA_ARGS__);


/** Types **/

enum env_action { ENV_END = 0,       // terminate list of environment changes
                  ENV_SET_DEFAULT,   // set by /ch/environment within image
                  ENV_SET_VARS,      // set by list of variables
                  ENV_UNSET_GLOB };  // unset glob matches

struct env_var {
   char *name;
   char *value;
};

struct env_delta {
   enum env_action action;
   union {
      struct env_var *vars;  // ENV_SET_VARS
      char *glob;            // ENV_UNSET_GLOB
   } arg;
};

enum log_level { LL_FATAL =   -2,  // minimum number of -v to print the msg
                 LL_WARNING = -1,
                 LL_INFO =     0,
                 LL_VERBOSE =  1,
                 LL_DEBUG =    2,
                 LL_TRACE =    3 };


/** External variables **/

extern enum log_level verbose;
extern char *host_tmp;
extern char *username;
extern char *warnings;
extern size_t warnings_offset;
extern const size_t warnings_size;


/** Function prototypes **/

char *argv_to_string(char **argv);
bool buf_zero_p(void *buf, size_t size);
char *cat(const char *a, const char *b);
struct env_var *env_file_read(const char *path);
void env_set(const char *name, const char *value, const bool expand);
void env_unset(const char *glob);
struct env_var env_var_parse(const char *line, const char *path, size_t lineno);
void list_append(void **ar, void *new, size_t size);
void *list_new(size_t size, size_t ct);
void log_ids(const char *func, int line);
void mkdirs(const char *base, const char *path, char **denylist);
void msg(enum log_level level, const char *file, int line, int errno_,
         const char *fmt, ...);
noreturn void msg_fatal(const char *file, int line, int errno_,
                        const char *fmt, ...);
bool path_exists(const char *path, struct stat *statbuf, bool follow_symlink);
unsigned long path_mount_flags(const char *path);
void path_split(const char *path, char **dir, char **base);
bool path_subdir_p(const char *base, const char *path);
char *realpath_(const char *path, bool fail_ok);
void replace_char(char *str, char old, char new);
void split(char **a, char **b, const char *str, char del);
void version(void);
size_t warnings_append(char *addr, char *str, size_t size, size_t offset);
void warnings_reprint(void);
