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
const char *VERBOSE_LEVELS[] = { "error",
                                 "warning",
                                 "info",
                                 "verbose",
                                 "debug" };


/** External variables **/

/* Level of chatter on stderr desired (0-3). */
int verbose;

/* Path to host temporary directory. Set during command line processing. */
char *host_tmp = NULL;

/* Username of invoking users. Set during command line processing. */
char *username = NULL;


/** Function prototypes (private) **/

// none


/** Functions **/

/* Return true if buffer buf of length size is all zeros, false otherwise. */
bool buf_zero_p(void *buf, size_t size)
{
   for (size_t i = 0; i < size; i++)
      if (((char *)buf)[i] != 0)
         return false;
   return true;
}

/* Concatenate strings a and b, then return the result. */
char *cat(const char *a, const char *b)
{
   char *ret;
   if (a == NULL)
      a = "";
   if (b == NULL)
       b = "";
   T_ (asprintf(&ret, "%s%s", a, b) == strlen(a) + strlen(b));
   return ret;
}

/* Copy the buffer of size size pointed to by new into the last position in
   the zero-terminated array of elements with the same size on the heap
   pointed to by *ar, reallocating it to hold one more element and setting
   list to the new location. *list can be NULL to initialize a new list.
   Return the new array size.

   Note: ar must be cast, e.g. "list_append((void **)&foo, ...)".

   Warning: This function relies on all pointers having the same
   representation, which is true on most modern machines but is not guaranteed
   by the standard [1]. We could instead return the new value of ar rather
   than using an out parameter, which would avoid the double pointer and
   associated non-portability but make it easy for callers to create dangling
   pointers, i.e., after "a = list_append(b, ...)", b will dangle. That
   problem could in turn be avoided by returning a *copy* of the array rather
   than a modified array, but then the caller has to deal with the original
   array itself. It seemed to me the present behavior was the best trade-off.

   [1]: http://www.c-faq.com/ptrs/genericpp.html */
void list_append(void **ar, void *new, size_t size)
{
   int ct;
   T_ (new != NULL);

   // count existing elements
   if (*ar == NULL)
      ct = 0;
   else
      for (ct = 0; !buf_zero_p((char *)*ar + ct*size, size); ct++)
         ;

   T_ (*ar = realloc(*ar, (ct+2)*size));        // existing + new + terminator
   memcpy((char *)*ar + ct*size, new, size);    // append new (no overlap)
   memset((char *)*ar + (ct+1)*size, 0, size);  // set new terminator
}

/* Return a pointer to a new, empty zero-terminated array containing elements
   of size size, with room for ct elements without re-allocation. The latter
   allows to pre-allocate an arbitrary number of slots in the list, which can
   then be filled directly without testing the list's length for each one.
   (The list is completely filled with zeros, so every position has a
   terminator after it.) */
void *list_new(size_t size, size_t ct)
{
   void *list;
   T_ (list = calloc(ct+1, size));
   return list;
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

/* Create directories in path under base. Exit with an error if anything goes
   wrong. For example, mkdirs("/foo", "/bar/baz") will create directories
   /foo/bar and /foo/bar/baz if they don't already exist, but /foo must exist
   already. Symlinks are followed. path must remain under base, i.e. you can't
   use symlinks or ".." to climb out. denylist is a null-terminated array of
   paths under which no directories may be created, or NULL if none. */
void mkdirs(const char *base, const char *path, char **denylist)
{
   char *basec, *component, *next, *nextc, *pathw, *saveptr;
   char *denylist_null[] = { NULL };
   struct stat sb;

   T_ (base[0] != 0   && path[0] != 0);      // no empty paths
   T_ (base[0] == '/' && path[0] == '/');    // absolute paths only
   if (denylist == NULL)
      denylist = denylist_null;  // literal here causes intermittent segfaults

   basec = realpath_safe(base);

   DEBUG("mkdirs: base: %s", basec);
   DEBUG("mkdirs: path: %s", path);
   for (size_t i = 0; denylist[i] != NULL; i++)
      DEBUG("mkdirs: deny: %s", denylist[i]);

   pathw = cat(path, "");  // writeable copy
   saveptr = NULL;         // avoid warning (#1048; see also strtok_r(3))
   component = strtok_r(pathw, "/", &saveptr);
   nextc = basec;
   while (component != NULL) {
      next = cat(nextc, "/");
      next = cat(next, component);  // canonical except for last component
      DEBUG("mkdirs: next: %s", next)
      component = strtok_r(NULL, "/", &saveptr);  // next NULL if current last
      if (path_exists(next, &sb, false)) {
         if (S_ISLNK(sb.st_mode)) {
            char buf;                             // we only care if absolute
            Tf (1 == readlink(next, &buf, 1), "can't read symlink: %s", next);
            Tf (buf != '/', "can't mkdir: symlink not relative: %s", next);
            Te (path_exists(next, &sb, true),     // resolve symlink
                "can't mkdir: broken symlink: %s", next);
         }
         Tf (S_ISDIR(sb.st_mode) || !component,   // last component not dir OK
             "can't mkdir: exists but not a directory: %s", next);
         nextc = realpath_safe(next);
         DEBUG("mkdirs: exists, canonical: %s", nextc);
      } else {
         Te (path_subdir_p(basec, next),
             "can't mkdir: %s not subdirectory of %s", next, basec);
         for (size_t i = 0; denylist[i] != NULL; i++)
            Ze (path_subdir_p(denylist[i], next),
                "can't mkdir: %s under existing bind-mount %s",
                next, denylist[i]);
         Zf (mkdir(next, 0777), "can't mkdir: %s", next);
         nextc = next;  // canonical b/c we just created last component as dir
         DEBUG("mkdirs: created: %s", nextc)
      }
   }
   DEBUG("mkdirs: done");
}

/* Print a formatted message on stderr if the level warrants it. Levels:

     0 : "error"   : always print; exit unsuccessfully afterwards
     1 : "warning" : always print
     2 : "info"    : print if verbose >= 2
     3 : "verbose" : print if verbose >= 3
     4 : "debug"   : print if verbose >= 4 */
void msg(int level, const char *file, int line, int errno_,
         const char *fmt, ...)
{
   va_list ap;

   if (level > verbose)
      return;

   fprintf(stderr, "%s[%d]: ", program_invocation_short_name, getpid());

   if (level <= 1 && fmt != NULL)
      fprintf(stderr, "%s: ", VERBOSE_LEVELS[level]);

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

/* Return true if the given path exists, false otherwise. On error, exit. If
   statbuf is non-null, store the result of stat(2) there. If follow_symlink
   is true and the last component of path is a symlink, stat(2) the target of
   the symlnk; otherwise, lstat(2) the link itself. */
bool path_exists(const char *path, struct stat *statbuf, bool follow_symlink)
{
   struct stat statbuf_;

   if (statbuf == NULL)
      statbuf = &statbuf_;

   if (follow_symlink) {
      if (stat(path, statbuf) == 0)
         return true;
   } else {
      if (lstat(path, statbuf) == 0)
         return true;
   }

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
unsigned long path_mount_flags(const char *path)
{
   struct statvfs sv;
   unsigned long known_flags =   ST_MANDLOCK   | ST_NOATIME  | ST_NODEV
                               | ST_NODIRATIME | ST_NOEXEC   | ST_NOSUID
                               | ST_RDONLY     | ST_RELATIME | ST_SYNCHRONOUS;

   Z_ (statvfs(path, &sv));

   // Flag 0x20 is ST_VALID according to the kernel [1], which clashes with
   // MS_REMOUNT, so inappropriate to pass through. Glibc deletes it from the
   // flags returned by statvfs(2) [2], but musl doesn’t [3], so delete it.
   //
   // [1]: https://github.com/torvalds/linux/blob/3644286f/include/linux/statfs.h#L27
   // [2]: https://sourceware.org/git?p=glibc.git;a=blob;f=sysdeps/unix/sysv/linux/internal_statvfs.c;h=b1b8dfefe6be909339520d120473bd67e4bece57
   // [3]: https://git.musl-libc.org/cgit/musl/tree/src/stat/statvfs.c?h=v1.2.2
   sv.f_flag ^= 0x20;

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
void path_split(const char *path, char **dir, char **base)
{
   char *path2;

   T_ (path2 = strdup(path));
   *dir = dirname(path2);
   T_ (path2 = strdup(path));
   *base = basename(path2);
}

/* Return true if path is a subdirectory of base, false otherwise. Acts on the
   paths as given, with no canonicalization or other reference to the
   filesystem. For example:

      path_subdir_p("/foo", "/foo/bar")   => true
      path_subdir_p("/foo", "/bar")       => false
      path_subdir_p("/foo/bar", "/foo/b") => false */
bool path_subdir_p(const char *base, const char *path)
{
   int base_len = strlen(base);

   if (base_len > strlen(path))
      return false;

   if (!strcmp(base, "/"))  // below logic breaks if base is root
      return true;

   return (   !strncmp(base, path, base_len)
           && (path[base_len] == '/' || path[base_len] == 0));
}

/* Like realpath(3), but exit with error on failure. */
char *realpath_safe(const char *path)
{
   char *pathc;

   pathc = realpath(path, NULL);
   Tf (pathc != NULL, "can't canonicalize: %s", path);
   return pathc;
}

/* Split string str at first instance of delimiter del. Set *a to the part
   before del, and *b to the part after. Both can be empty; if no token is
   present, set both to NULL. Unlike strsep(3), str is unchanged; *a and *b
   point into a new buffer allocated with malloc(3). This has two
   implications: (1) the caller must free(3) *a but not *b, and (2) the parts
   can be rejoined by setting *(*b-1) to del. The point here is to provide an
   easier wrapper for strsep(3). */
void split(char **a, char **b, const char *str, char del)
{
   char *tmp;
   char delstr[2] = { del, 0 };
   T_ (str != NULL);
   tmp = strdup(str);
   *b = tmp;
   *a = strsep(b, delstr);
   if (*b == NULL)
      *a = NULL;
}

/* Report the version number. */
void version(void)
{
   fprintf(stderr, "%s\n", VERSION);
}
