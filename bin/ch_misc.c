/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <libgen.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include "config.h"
#include "ch_misc.h"


/** Macros **/

/* Number of supplemental GIDs we can deal with. */
#define SUPP_GIDS_MAX 128


/** Constants **/

/* Names of verbosity levels. */
const char *VERBOSE_LEVELS[] = { "error", "warning", "info", "debug" };


/** External variables **/

/* Level of chatter on stderr desired (0-3). */
int verbose;


/** Function prototypes (private) **/

// none


/** Functions **/

/* Concatenate strings a and b, then return the result. */
char *cat(char *a, char *b)
{
   char *ret;

   T_ (1 <= asprintf(&ret, "%s%s", a, b));
   return ret;
}

/* If verbose, print uids and gids on stderr prefixed with where. */
void log_ids(const char *func, int line)
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;
   gid_t supp_gids[SUPP_GIDS_MAX];
   int supp_gid_ct;

   if (verbose >= 3) {
      Z_ (getresuid(&ruid, &euid, &suid));
      Z_ (getresgid(&rgid, &egid, &sgid));
      fprintf(stderr, "%s %d: uids=%d,%d,%d, gids=%d,%d,%d + ", func, line,
              ruid, euid, suid, rgid, egid, sgid);
      supp_gid_ct = getgroups(SUPP_GIDS_MAX, supp_gids);
      if (supp_gid_ct == -1) {
         T_ (errno == EINVAL);
         Te (0, "more than %d groups", SUPP_GIDS_MAX);
      }
      for (int i = 0; i < supp_gid_ct; i++) {
         if (i > 0)
            fprintf(stderr, ",");
         fprintf(stderr, "%d", supp_gids[i]);
      }
      fprintf(stderr, "\n");
   }
}

/* Print a formatted message on stderr if the level warrants it. Levels:

     0 : "error"   : always print; exit unsuccessfully afterwards
     1 : "warning" : always print
     1 : "info"    : print if verbose >= 2
     2 : "debug"   : print if verbose >= 3 */
void msg(int level, char *file, int line, int errno_, char *fmt, ...)
{
   va_list ap;

   if (level > verbose)
      return;

   fprintf(stderr, "%s[%d]: ", program_invocation_short_name, getpid());

   if (fmt == NULL)
      fputs(VERBOSE_LEVELS[level], stderr);
   else {
      va_start(ap, fmt);
      vfprintf(stderr, fmt, ap);
      va_end(ap);
   }

   if (errno_)
      fprintf(stderr, ": %s (%s:%d %d)\n",
              strerror(errno_), file, line, errno_);
   else
      fprintf(stderr, " (%s:%d)\n", file, line);

   if (level == 0)
      exit(EXIT_FAILURE);
}

/* Return true if the given path exists, false otherwise. On error, exit. */
bool path_exists(char *path)
{
   struct stat sb;

   if (stat(path, &sb) == 0)
      return true;

   Tf (errno == ENOENT, "can't stat: %s", path);
   return false;
}

/* Return the mount flags of the file system containing path, suitable for
   passing to mount(2).

   This is messy because, the flags we get from statvfs(3) are ST_* while the
   flags needed by mount(2) are MS_*. My glibc has a comment in bits/statvfs.h
   that the ST_* "should be kept in sync with" the MS_* flags, and the values
   do seem to match, but there are additional undocumented flags in there.
   Also, the kernel contains a test "unprivileged-remount-test.c" that
   manually translates the flags. Thus, I wasn't comfortable simply passing
   the output of statvfs(3) to mount(2). */
unsigned long path_mount_flags(char *path)
{
   struct statvfs sv;
   unsigned long known_flags =   ST_MANDLOCK   | ST_NOATIME  | ST_NODEV
                               | ST_NODIRATIME | ST_NOEXEC   | ST_NOSUID
                               | ST_RDONLY     | ST_RELATIME | ST_SYNCHRONOUS;

   Z_ (statvfs(path, &sv));
   Ze (sv.f_flag & ~known_flags, "unknown mount flags: 0x%lx %s",
       sv.f_flag & ~known_flags, path);

   return   (sv.f_flag & ST_MANDLOCK    ? MS_MANDLOCK    : 0)
          | (sv.f_flag & ST_NOATIME     ? MS_NOATIME     : 0)
          | (sv.f_flag & ST_NODEV       ? MS_NODEV       : 0)
          | (sv.f_flag & ST_NODIRATIME  ? MS_NODIRATIME  : 0)
          | (sv.f_flag & ST_NOEXEC      ? MS_NOEXEC      : 0)
          | (sv.f_flag & ST_NOSUID      ? MS_NOSUID      : 0)
          | (sv.f_flag & ST_RDONLY      ? MS_RDONLY      : 0)
          | (sv.f_flag & ST_RELATIME    ? MS_RELATIME    : 0)
          | (sv.f_flag & ST_SYNCHRONOUS ? MS_SYNCHRONOUS : 0);
}

/* Split path into dirname and basename. */
void path_split(char *path, char **dir, char **base)
{
   char *path2;

   T_ (path2 = strdup(path));
   *dir = dirname(path2);
   T_ (path2 = strdup(path));
   *base = basename(path2);
}

/* Split string str at first instance of delimiter del. Set *a to the part
   before del, and *b to the part after. Both can be empty; if no token is
   present, set both to NULL. Unlike strsep(3), str is unchanged; *a and *b
   point into a new buffer allocated with malloc(3). This has two
   implications: (1) the caller must free(3) *a but not *b, and (2) the parts
   can be rejoined by setting *(*b-1) to del. The point here is to provide an
   easier wrapper for strsep(3). */
void split(char **a, char **b, char *str, char del)
{
   char delstr[2] = { del, 0 };
   T_ (str != NULL);
   str = strdup(str);
   *b = str;
   *a = strsep(b, delstr);
   if (*b == NULL)
      *a = NULL;
}

/* Report the version number. */
void version(void)
{
   fprintf(stderr, "%s\n", VERSION);
}
