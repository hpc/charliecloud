/* Copyright © Triad National Security, LLC, and others.

   This interface contains miscellaneous utility features. It is separate so
   that peripheral Charliecloud C programs don't have to link in the extra
   libraries that ch_core requires. */

#define _GNU_SOURCE
#pragma once

#include <dirent.h>
#include <errno.h>
#include <stdbool.h>
#include <stdlib.h>
#include <sys/stat.h>


/** Macros **/

/* Log the current UIDs. */
#define LOG_IDS log_ids(__func__, __LINE__)

/* C99 does not have noreturn or _Noreturn (those are C11), but GCC, Clang,
   and hopefully others support the following extension. */
#define noreturn __attribute__ ((noreturn))

/* Syslog facility and level we use. */
#ifdef ENABLE_SYSLOG
#define SYSLOG_PRI (LOG_USER|LOG_INFO)
#endif

/* Size of “warnings” buffer, in bytes. We want this to be big enough that we
   don’t need to worry about running out of room. */
#define WARNINGS_SIZE (4*1024)

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

#define FATAL(...)   msg_fatal(      __FILE__, __LINE__, 0, __VA_ARGS__)
#define WARNING(...) msg(LL_WARNING, __FILE__, __LINE__, 0, __VA_ARGS__)
#define INFO(...)    msg(LL_INFO,    __FILE__, __LINE__, 0, __VA_ARGS__)
#define VERBOSE(...) msg(LL_VERBOSE, __FILE__, __LINE__, 0, __VA_ARGS__)
#define DEBUG(...)   msg(LL_DEBUG,   __FILE__, __LINE__, 0, __VA_ARGS__)
#define TRACE(...)   msg(LL_TRACE,   __FILE__, __LINE__, 0, __VA_ARGS__)


/** Types **/

#ifndef HAVE_COMPARISON_FN_T
typedef int (*comparison_fn_t) (const void *, const void *);
#endif

struct env_var {
   char *name;
   char *value;
};

enum log_level { LL_FATAL =   -3,
                 LL_STDERR =  -2,
                 LL_WARNING = -1,
                 LL_INFO =     0,  // minimum number of -v to print the msg
                 LL_VERBOSE =  1,
                 LL_DEBUG =    2,
                 LL_TRACE =    3 };

enum log_color_when { LL_COLOR_NULL = 0,
                      LL_COLOR_AUTO,
                      LL_COLOR_YES,
                      LL_COLOR_NO };

enum log_test { LL_TEST_NONE  = 0,
                LL_TEST_YES   = 1,
                LL_TEST_FATAL = 2 };


/** External variables **/

extern bool abort_fatal;
extern bool log_color_p;
extern char *host_tmp;
extern char *username;
extern enum log_level verbose;
extern char *warnings;
extern size_t warnings_offset;


/** Function prototypes **/

char *argv_to_string(char **argv);
const char *bool_to_string(bool b);
int buf_strings_count(char *str, size_t s);
bool buf_zero_p(void *buf, size_t size);
char *cat(const char *a, const char *b);
char *cats(size_t argc, ...);
char **dir_glob(const char *path, const char *glob);
int dir_glob_count(const char *path, const char *glob);
struct env_var *env_file_read(const char *path, int delim);
char *env_get(const char *name, char *value_default);
void env_set(const char *name, const char *value, const bool expand);
void envs_set(const struct env_var *envs, const bool expand);
void envs_unset(const char *glob);
struct env_var env_var_parse(const char *line, const char *path, size_t lineno);
void list_append(void **ar, void *new, size_t size);
void list_cat(void **dst, void *src, size_t size);
size_t list_count(void *ar, size_t size);
void *list_new_strings(char delim, const char *s);
void *list_new(size_t size, size_t ct);
void log_ids(const char *func, int line);
void logging_init(enum log_color_when when, enum log_test test);
void test_logging(bool fail);
void mkdirs(const char *base, const char *path, char **denylist,
            const char *scratch);
void msg(enum log_level level, const char *file, int line, int errno_,
         const char *fmt, ...);
noreturn void msg_fatal(const char *file, int line, int errno_,
                        const char *fmt, ...);
bool path_exists(const char *path, struct stat *statbuf, bool follow_symlink);
char *path_join(const char *a, const char *b);
unsigned long path_mount_flags(const char *path);
void path_split(const char *path, char **dir, char **base);
bool path_subdir_p(const char *base, const char *path);
char *realpath_(const char *path, bool fail_ok);
void replace_char(char *str, char old, char new);
void split(char **a, char **b, const char *str, char del);
void version(void);
size_t string_append(char *addr, char *str, size_t size, size_t offset);
void warnings_reprint(void);
