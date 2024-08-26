#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <fcntl.h>
#include <fnmatch.h>
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

/* FNM_EXTMATCH is a GNU extension to support extended globs in fnmatch(3).
   If not available, define as 0 to ignore this flag. */
#ifndef HAVE_FNM_EXTMATCH
#define FNM_EXTMATCH 0
#endif

/* Number of supplemental GIDs we can deal with. */
#define SUPP_GIDS_MAX 128


/** External variables **/

/* Level of chatter on stderr. */
enum log_level verbose;

/* Path to host temporary directory. Set during command line processing. */
char *host_tmp = NULL;

/* Username of invoking users. Set during command line processing. */
char *username = NULL;

/* List of warnings to be re-printed on exit. This is a buffer of shared memory
   allocated by mmap(2), structured as a sequence of null-terminated character
   strings. Warnings that do not fit in this buffer will be lost, though we
   allocate enough memory that this is unlikely. See “string_append()” for
   more details. */
char *warnings;

/* Current byte offset from start of “warnings” buffer. This gives the address
   where the next appended string will start. This means that the null
   terminator of the previous string is warnings_offset - 1. */
size_t warnings_offset = 0;


/** Function prototypes (private) **/

void mkdir_overmount(const char *path, const char *scratch);
void msgv(enum log_level level, const char *file, int line, int errno_,
          const char *fmt, va_list ap);


/** Functions **/

/* Serialize the null-terminated vector of arguments argv and return the
   result as a newly allocated string. The purpose is to provide a
   human-readable reconstruction of a command line where each argument can
   also be recovered byte-for-byte; see ch-run(1) for details. */
char *argv_to_string(char **argv)
{
   char *s = NULL;

   for (size_t i = 0; argv[i] != NULL; i++) {
      char *argv_, *x;
      bool quote_p = false;

      // Max length is escape every char plus two quotes and terminating zero.
      T_ (argv_ = calloc(2 * strlen(argv[i]) + 3, 1));

      // Copy to new string, escaping as we go. Note lots of fall-through. I'm
      // not sure where this list of shell meta-characters came from; I just
      // had it on hand already from when we were deciding on the image
      // reference transformation for filesystem paths.
      for (size_t ji = 0, jo = 0; argv[i][ji] != 0; ji++) {
         char c = argv[i][ji];
         if (isspace(c) || !isascii(c) || !isprint(c))
            quote_p = true;
         switch (c) {
         case '!':   // history expansion
         case '"':   // string delimiter
         case '$':   // variable expansion
         case '\\':  // escape character
         case '`':   // output expansion
            argv_[jo++] = '\\';
         case '#':   // comment
         case '%':   // job ID
         case '&':   // job control
         case '\'':  // string delimiter
         case '(':   // subshell grouping
         case ')':   // subshell grouping
         case '*':   // globbing
         case ';':   // command separator
         case '<':   // redirect
         case '=':   // globbing
         case '>':   // redirect
         case '?':   // globbing
         case '[':   // globbing
         case ']':   // globbing
         case '^':   // command “quick substitution”
         case '{':   // command grouping
         case '|':   // pipe
         case '}':   // command grouping
         case '~':   // home directory expansion
            quote_p = true;
         default:
            argv_[jo++] = c;
            break;
         }
      }

      if (quote_p) {
         x = argv_;
         T_ (1 <= asprintf(&argv_, "\"%s\"", argv_));
         free(x);
      }

      if (i != 0) {
         x = s;
         s = cat(s, " ");
         free(x);
      }

      x = s;
      s = cat(s, argv_);
      free(x);
      free(argv_);
   }

   return s;
}

/* Iterate through buffer “buf” of size “s” consisting of null-terminated
   strings and return the number of strings in it. Key assumptions:

      1. The buffer has been initialized to zero, i.e. all bytes that have not
         been explicitly set are null.

      2. All strings have been appended to the buffer in full without
         truncation, including their null terminator.

      3. The buffer contains no empty strings.

   These assumptions are consistent with the construction of the “warnings”
   shared memory buffer, which is the main justification for this function. Note
   that under these assumptions, the final byte in the buffer is guaranteed to
   be null. */
int buf_strings_count(char *buf, size_t size)
{
   int count = 0;

   if (buf[0] != '\0') {
      for (size_t i = 0; i < size; i++)
         if (buf[i] == '\0') {                     // found string terminator
            count++;
            if (i < size - 1 && buf[i+1] == '\0')  // two term. in a row; done
               break;
         }
   }

   return count;
}

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

/* Like scandir(3), but (1) filter excludes “.” and “..”, (2) results are not
   sorted, and (3) cannot fail (exits with an error instead). */
int dir_ls(const char *path, struct dirent ***namelist)
{
   int entry_ct;

   entry_ct = scandir(path, namelist, dir_ls_filter, NULL);
   Tf (entry_ct >= 0, "can't scan dir", path);
   return entry_ct;
}

/* Return the number of entries in directory path, not including “.” and “..”;
   i.e., the empty directory returns 0 despite them. */
int dir_ls_count(const char *path)
{
   int ct;
   struct dirent **namelist;

   ct = dir_ls(path, &namelist);
   for (size_t i = 0; i < ct; i++)
      free(namelist[i]);
   free(namelist);

   return ct;
}

/* scandir(3) filter that excludes “.” and “..”: Return 0 if e->d_name is one
   of those strings, else 1. */
int dir_ls_filter(const struct dirent *e)
{
   return !(!strcmp(e->d_name, ".") || !strcmp(e->d_name, ".."));
}

/* Read the file listing environment variables at path, with records separated
   by delim, and return a corresponding list of struct env_var. Reads the
   entire file one time without seeking. If there is a problem reading the
   file, or with any individual variable, exit with error.

   The purpose of delim is to allow both newline- and zero-delimited files. We
   did consider using a heuristic to choose the file’s delimiter, but there
   seemed to be two problems. First, every heuristic we considered had flaws.
   Second, use of a heuristic would require reading the file twice or seeking.
   We don’t want to demand non-seekable files (e.g., pipes), and if we read
   the file into a buffer before parsing, we’d need our own getdelim(3). See
   issue #1124 for further discussion. */
struct env_var *env_file_read(const char *path, int delim)
{
   struct env_var *vars;
   FILE *fp;

   Tf (fp = fopen(path, "r"), "can't open: %s", path);

   vars = list_new(sizeof(struct env_var), 0);
   for (size_t line_no = 1; true; line_no++) {
      struct env_var var;
      char *line = NULL;
      size_t line_len = 0;  // don't care but required by getline(3)
      errno = 0;
      if (-1 == getdelim(&line, &line_len, delim, fp)) {
         if (errno == 0)    // EOF
            break;
         else
            Tf (0, "can't read: %s", path);
      }
      if (line[strlen(line) - 1] == '\n')  // rm newline if present
         line[strlen(line) - 1] = 0;
      if (line[0] == 0)                    // skip blank lines
         continue;
      var = env_var_parse(line, path, line_no);
      list_append((void **)&vars, &var, sizeof(var));
   }

   Zf (fclose(fp), "can't close: %s", path);
   return vars;
}

/* Set environment variable name to value. If expand, then further expand
   variables in value marked with "$" as described in the man page. */
void env_set(const char *name, const char *value, const bool expand)
{
   char *value_, *value_expanded;
   bool first_written;

   // Walk through value fragments separated by colon and expand variables.
   T_ (value_ = strdup(value));
   value_expanded = "";
   first_written = false;
   while (true) {                               // loop executes ≥ once
      char *fgmt = strsep(&value_, ":");        // NULL -> no more items
      if (fgmt == NULL)
         break;
      if (expand && fgmt[0] == '$' && fgmt[1] != 0) {
         fgmt = getenv(fgmt + 1);               // NULL if unset
         if (fgmt != NULL && fgmt[0] == 0)
            fgmt = NULL;                        // convert empty to unset
      }
      if (fgmt != NULL) {                       // NULL -> omit from output
         if (first_written)
            value_expanded = cat(value_expanded, ":");
         value_expanded = cat(value_expanded, fgmt);
         first_written = true;
      }
   }

   // Save results.
   VERBOSE("environment: %s=%s", name, value_expanded);
   Z_ (setenv(name, value_expanded, 1));
}

/* Remove variables matching glob from the environment. This is tricky,
   because there is no standard library function to iterate through the
   environment, and the environ global array can be re-ordered after
   unsetenv(3) [1]. Thus, the only safe way without additional storage is an
   O(n^2) search until no matches remain.

   Our approach is O(n): we build up a copy of environ, skipping variables
   that match the glob, and then assign environ to the copy. (This is a valid
   thing to do [2].)

   [1]: https://unix.stackexchange.com/a/302987
   [2]: http://man7.org/linux/man-pages/man3/exec.3p.html */
void env_unset(const char *glob)
{
   char **new_environ = list_new(sizeof(char *), 0);
   for (size_t i = 0; environ[i] != NULL; i++) {
      char *name, *value;
      int matchp;
      split(&name, &value, environ[i], '=');
      T_ (name != NULL);          // environ entries must always have equals
      matchp = fnmatch(glob, name, FNM_EXTMATCH); // extglobs if available
      if (matchp == 0) {
         VERBOSE("environment: unset %s", name);
      } else {
         T_ (matchp == FNM_NOMATCH);
         *(value - 1) = '=';  // rejoin line
         list_append((void **)&new_environ, &name, sizeof(name));
      }
   }
   environ = new_environ;
}

/* Parse the environment variable in line and return it as a struct env_var.
   Exit with error on syntax error; if path is non-NULL, attribute the problem
   to that path at line_no. Note: Trailing whitespace such as newline is
   *included* in the value. */
struct env_var env_var_parse(const char *line, const char *path, size_t lineno)
{
   char *name, *value, *where;

   if (path == NULL) {
      T_ (where = strdup(line));
   } else {
      T_ (1 <= asprintf(&where, "%s:%zu", path, lineno));
   }

   // Split line into variable name and value.
   split(&name, &value, line, '=');
   Te (name != NULL, "can't parse variable: no delimiter: %s", where);
   Te (name[0] != 0, "can't parse variable: empty name: %s", where);
   free(where);  // for Tim

   // Strip leading and trailing single quotes from value, if both present.
   if (   strlen(value) >= 2
       && value[0] == '\''
       && value[strlen(value) - 1] == '\'') {
      value[strlen(value) - 1] = 0;
      value++;
   }

   return (struct env_var){ name, value };
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

void test_logging(bool fail) {
   TRACE("trace");
   DEBUG("debug");
   VERBOSE("verbose");
   INFO("info");
   WARNING("warning");
   if (fail)
      FATAL(0, "the program failed inexplicably (\"log-fail\" specified)");
   exit(0);
}

/* Create the directory at path, despite its parent not allowing write access,
   by overmounting a new, writeable directory atop it. We preserve the old
   contents by bind-mounting the old directory as a subdirectory, then setting
   up a symlink ranch.

   The new directory lives initially in scratch, which must not be used for
   any other purpose. No cleanup is done here, so a disposable tmpfs is best.
   If anything goes wrong, exit with an error message. */
void mkdir_overmount(const char *path, const char *scratch)
{
   char *parent, *path2, *over, *path_dst;
   char *orig_dir = ".orig";  // resisted calling this .weirdal
   int entry_ct;
   struct dirent **entries;

   VERBOSE("making writeable via symlink ranch: %s", path);
   path2 = strdup(path);
   parent = dirname(path2);
   T_ (1 <= asprintf(&over, "%s/%d", scratch, dir_ls_count(scratch) + 1));
   path_dst = path_join(over, orig_dir);

   // bind-mounts
   Z_ (mkdir(over, 0755));
   Z_ (mkdir(path_dst, 0755));
   Zf (mount(parent, path_dst, NULL, MS_REC|MS_BIND, NULL),
       "can't bind-mount: %s -> %s", parent, path_dst);
   Zf (mount(over, parent, NULL, MS_REC|MS_BIND, NULL),
       "can't bind-mount: %s- > %s", over, parent);

   // symlink ranch
   entry_ct = dir_ls(path_dst, &entries);
   DEBUG("existing entries: %d", entry_ct);
   for (int i = 0; i < entry_ct; i++) {
      char * src = path_join(parent, entries[i]->d_name);
      char * dst = path_join(orig_dir, entries[i]->d_name);

      Zf (symlink(dst, src), "can't symlink: %s -> %s", src, dst);

      free(src);
      free(dst);
      free(entries[i]);
   }
   free(entries);

   Zf (mkdir(path, 0755), "can't mkdir even after overmount: %s", path);

   free(path_dst);
   free(over);
   free(path2);
}

/* Create directories in path under base. Exit with an error if anything goes
   wrong. For example, mkdirs("/foo", "/bar/baz") will create directories
   /foo/bar and /foo/bar/baz if they don't already exist, but /foo must exist
   already. Symlinks are followed. path must remain under base, i.e. you can't
   use symlinks or ".." to climb out. denylist is a null-terminated array of
   paths under which no directories may be created, or NULL if none.

   Can defeat an un-writeable directory by overmounting a new writeable
   directory atop it. To enable this behavior, pass the path to an appropriate
   scratch directory in scratch. */
void mkdirs(const char *base, const char *path, char **denylist,
            const char *scratch)
{
   char *basec, *component, *next, *nextc, *pathw, *saveptr;
   char *denylist_null[] = { NULL };
   struct stat sb;

   T_ (base[0] != 0   && path[0] != 0);      // no empty paths
   T_ (base[0] == '/' && path[0] == '/');    // absolute paths only
   if (denylist == NULL)
      denylist = denylist_null;  // literal here causes intermittent segfaults

   basec = realpath_(base, false);

   TRACE("mkdirs: base: %s", basec);
   TRACE("mkdirs: path: %s", path);
   for (size_t i = 0; denylist[i] != NULL; i++)
      TRACE("mkdirs: deny: %s", denylist[i]);

   pathw = cat(path, "");  // writeable copy
   saveptr = NULL;         // avoid warning (#1048; see also strtok_r(3))
   component = strtok_r(pathw, "/", &saveptr);
   nextc = basec;
   next = NULL;
   while (component != NULL) {
      next = cat(nextc, "/");
      next = cat(next, component);  // canonical except for last component
      TRACE("mkdirs: next: %s", next)
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
         nextc = realpath_(next, false);
         TRACE("mkdirs: exists, canonical: %s", nextc);
      } else {
         Te (path_subdir_p(basec, next),
             "can't mkdir: %s not subdirectory of %s", next, basec);
         for (size_t i = 0; denylist[i] != NULL; i++)
            Ze (path_subdir_p(denylist[i], next),
                "can't mkdir: %s under existing bind-mount %s",
                next, denylist[i]);
         if (mkdir(next, 0755)) {
            if (scratch && (errno == EACCES || errno == EPERM))
               mkdir_overmount(next, scratch);
            else
               Tf (0, "can't mkdir: %s", next);
         }
         nextc = next;  // canonical b/c we just created last component as dir
         TRACE("mkdirs: created: %s", nextc)
      }
   }
   TRACE("mkdirs: done");
}

/* Print a formatted message on stderr if the level warrants it. */
void msg(enum log_level level, const char *file, int line, int errno_,
         const char *fmt, ...)
{
   va_list ap;

   va_start(ap, fmt);
   msgv(level, file, line, errno_, fmt, ap);
   va_end(ap);
}

void msg_error(const char *file, int line, int errno_,
               const char *fmt, ...)
{
   va_list ap;

   va_start(ap, fmt);
   /* We print errors at LL_FATAL because, according to our documentation,
      errors are never suppressed. Perhaps we need to rename this log level (see
      issue #1914). */
   msgv(LL_FATAL, file, line, errno_, fmt, ap);
   va_end(ap);
}

/* Note that msg_fatal doesn’t call msg_error like we do in the Python code
   because the variable number of arguments make it easier to simply define
   separate functions. */
noreturn void msg_fatal(const char *file, int line, int errno_,
                       const char *fmt, ...)
{
   va_list ap;

   va_start(ap, fmt);
   msgv(LL_FATAL, file, line, errno_, fmt, ap);
   va_end(ap);

   exit(EXIT_MISC_ERR);
}

/* va_list form of msg(). */
void msgv(enum log_level level, const char *file, int line, int errno_,
          const char *fmt, va_list ap)
{
   char *message, *ap_msg;

   if (level > verbose)
      return;

   T_ (1 <= asprintf(&message, "%s[%d]: ",
                     program_invocation_short_name, getpid()));

   // Prefix for the more urgent levels.
   switch (level) {
   case LL_FATAL:
      message = cat(message, "error: ");  // "fatal" too morbid for users
      break;
   case LL_WARNING:
      message = cat(message, "warning: ");
      break;
   default:
      break;
   }

   // Default message if not specified. Users should not see this.
   if (fmt == NULL)
      fmt = "please report this bug";

   T_ (1 <= vasprintf(&ap_msg, fmt, ap));
   if (errno_) {
      T_ (1 <= asprintf(&message, "%s%s: %s (%s:%d %d)", message, ap_msg,
                        strerror(errno_), file, line, errno_));
   } else {
      T_ (1 <= asprintf(&message, "%s%s (%s:%d)", message, ap_msg, file, line));
   }

   if (level == LL_WARNING) {
      warnings_offset += string_append(warnings, message, WARNINGS_SIZE,
                                       warnings_offset);
   }
   fprintf(stderr, "%s\n", message);
   if (fflush(stderr))
      abort();  // can't print an error b/c already trying to do that
}

/* Return true if the given path exists, false otherwise. On error, exit. If
   statbuf is non-null, store the result of stat(2) there. If follow_symlink
   is true and the last component of path is a symlink, stat(2) the target of
   the symlink; otherwise, lstat(2) the link itself. */
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

/* Concatenate paths a and b, then return the result. */
char *path_join(const char *a, const char *b)
{
   char *ret;

   T_ (a != NULL);
   T_ (strlen(a) > 0);
   T_ (b != NULL);
   T_ (strlen(b) > 0);

   T_ (asprintf(&ret, "%s/%s", a, b) == strlen(a) + strlen(b) + 1);

   return ret;
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
   // MS_REMOUNT, so inappropriate to pass through. Glibc unsets it from the
   // flag bits returned by statvfs(2) [2], but musl doesn’t [3], so unset it.
   //
   // [1]: https://github.com/torvalds/linux/blob/3644286f/include/linux/statfs.h#L27
   // [2]: https://sourceware.org/git?p=glibc.git;a=blob;f=sysdeps/unix/sysv/linux/internal_statvfs.c;h=b1b8dfefe6be909339520d120473bd67e4bece57
   // [3]: https://git.musl-libc.org/cgit/musl/tree/src/stat/statvfs.c?h=v1.2.2
   sv.f_flag &= ~0x20;

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
   T_ (*dir = strdup(dirname(path2)));
   free(path2);
   T_ (path2 = strdup(path));
   T_ (*base = strdup(basename(path2)));
   free(path2);
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
   int path_len = strlen(base);

   // remove trailing slashes
   while (base[base_len-1] == '/' && base_len >= 1)
      base_len--;
   while (path[path_len-1] == '/' && path_len >= 1)
      path_len--;

   if (base_len > path_len)
      return false;

   if (!strcmp(base, "/"))  // below logic breaks if base is root
      return true;

   return (   !strncmp(base, path, base_len)
           && (path[base_len] == '/' || path[base_len] == 0));
}

/* Like realpath(3), but never returns an error. If the underlying realpath(3)
   fails or path is NULL, and fail_ok is true, then return a copy of the
   input; otherwise (i.e., fail_ok is false) exit with error. */
char *realpath_(const char *path, bool fail_ok)
{
   char *pathc;

   if (path == NULL)
      return NULL;

   pathc = realpath(path, NULL);

   if (pathc == NULL) {
      if (fail_ok) {
         T_ (pathc = strdup(path));
      } else {
         Tf (false, "can't canonicalize: %s", path);
      }
   }

   return pathc;
}

/* Replace all instances of character “old” in “s” with “new”. */
void replace_char(char *s, char old, char new)
{
   for (int i = 0; s[i] != '\0'; i++)
      if(s[i] == old)
         s[i] = new;
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

/* Append null-terminated string “str” to the memory buffer “offset” bytes after
   from the address pointed to by “addr”. Buffer length is “size” bytes. Return
   the number of bytes written. If there isn’t enough room for the string, do
   nothing and return zero. */
size_t string_append(char *addr, char *str, size_t size, size_t offset)
{
   size_t written = strlen(str) + 1;

   if (size > (offset + written - 1))  // there is space
      memcpy(addr + offset, str, written);

   return written;
}

/* Reprint messages stored in “warnings” memory buffer. */
void warnings_reprint(void)
{
   size_t offset = 0;
   int warn_ct = buf_strings_count(warnings, WARNINGS_SIZE);

   if (warn_ct > 0)
      fprintf(stderr, "%s[%d]: warning: reprinting first %d warning(s)\n",
              program_invocation_short_name, getpid(), warn_ct);

   while (   warnings[offset] != 0
          || (offset < (WARNINGS_SIZE - 1) && warnings[offset+1] != 0)) {
      fputs(warnings + offset, stderr);
      fputc('\n', stderr);
      offset += strlen(warnings + offset) + 1;
   }

   if (fflush(stderr))
      abort();  // can't print an error b/c already trying to do that
}
