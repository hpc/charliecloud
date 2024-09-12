/* Re. zeroing newly-allocated memory:

   Because we use a lot of zero-terminated data structures, it would be nice
   for the allocation functions to return zeroed buffers. We also want to not
   require libgc, i.e., we want to still be able to use malloc(3) and
   realloc(3) under the hood. It’s easy to provide a zeroing
   malloc(3)-workalike, but as far as I can tell, it’s impossible to do so for
   realloc(3)-alike unless we either (1) maintain our own allocation size
   tracking or (2) use highly non-portable code. Neither of these seemed worth
   the effort and complexity.

   This is because, as it turns out, the length of an allocated buffer is a
   more complicated notion than it seems. A buffer has *two* different
   lengths: L1 is the size requested by the original caller, and L2 is the
   size actually allocated; L2 ≥ L1. Neither are reliably available:

     * L1: The allocator can’t provide it, and while the caller had it at the
       time of previous allocation, it might not have kept it.

     * L2: Not available from the libc allocator without fairly extreme
       non-portability and/or difficult constraints [1], though libgc does
       provide it with GC_size(). The caller never knew it.

   Suppose we call realloc() with a new length Lν, where Lν > L2 ≥ L1. To zero
   the new part of the buffer, we must zero (L1,Lν], or (L2,Lν] if we assume
   (L1,L2] are still zero from the initial malloc(), and leave prior bytes
   untouched. But we don’t know either L1 or L2 reliably, so we’re hosed,
   whether we call an upstream realloc() or malloc() an entirely new buffer,
   then memcpy(3).

   I suspect this is why libc provides calloc(3) but not an equivalent for
   realloc(3).

   [1]: https://stackoverflow.com/questions/1281686 */

#define _GNU_SOURCE

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>

#include "config.h"
#include "mem.h"
#include "misc.h"


/** Macros **/

/** Types **/

/** Constants **/

/** Globals **/

/* Size of the stack and heap at previous ch_memory_log() call. These are
   signed to avoid subtraction gotchas. */
ssize_t stack_prev = 0;
ssize_t heap_prev = 0;


/** Functions **/


/* Return a snprintf(3)-formatted string in a newly allocated buffer of
   appropriate length. Exit on error.

   This function formats the string twice: Once to figure out how long the
   formatted string is, and again to actually format the string. I’m not aware
   of a better way to compute string length. (musl does it the same way; glibc
   was too complicated for my patience in figuring it out.)

   An alternative would be to allocate a small buffer, try that, and if it’s
   too small re-allocate and format again. For strings that fit, this would
   save a formatting cycle at the cost of wasted memory and more code paths.
   That didn’t seem like the right trade-off, esp. since short strings should
   be the fastest to format. */
char *ch_asprintf(const char *fmt, ...)
{
   va_list ap1, ap2;
   int str_len;
   char *str;

   va_start(ap1, fmt);
   va_copy(ap2, ap1);

   T_ (0 <= (str_len = vsnprintf(NULL, 0, fmt, ap1)));
   str = ch_malloc(str_len + 1, false);
   T_ (str_len == vsnprintf(str, str_len + 1, fmt, ap2));

   va_end(ap1);
   va_end(ap2);

   return str;
}

/* Return a new null-terminated string containing the next record from fp,
   where records are delimited by delim (e.g., pass '\n' to get the next
   line). If no more records available, return NULL. Exit on error.

   Unlike getdelim(3), the delimiter is *not* part of the returned string.

   Warnings:

     1. Records cannot contain the zero byte, and behavior is undefined if fp
        containes any zeros and delimiter is not '\0'.

     2. The returned buffer is likely larger than needed. We assume wasting
        this space is better than the overhead of realloc’ing down to a
        precise size. */
char *ch_getdelim(FILE *fp, char delim)
{
   size_t bytes_read = 0;
   size_t buf_len = 8;  // non-zero start avoids early frequent realloc
   char *buf = ch_malloc(buf_len, false);

   while (true) {
      int c = fgetc(fp);
      if (c == EOF)
         break;
      bytes_read++;
      if (bytes_read > buf_len) {      // room for terminator ensured later
         buf_len *= 2;
         buf = ch_realloc(buf, buf_len, false);
      }
      buf[bytes_read-1] = c;
      if (c == delim)
         break;
   }

   if (buf[bytes_read-1] == delim) {   // found delimiter
      buf[bytes_read-1] = '\0';
   } else if (feof(fp)) {              // end-of-file
      if (bytes_read == 0)             // no record left
         return NULL;
      else {                           // record ends at EOF (no delimiter)
         if (bytes_read >= buf_len) {
            T_ (bytes_read == buf_len);
            buf = ch_realloc(buf, buf_len + 1, false);
         }
         buf[bytes_read] = '\n';
      }
   } else {                            // error
      Te (0, "error reading file");    // don’t know filename here
   }

   return buf;
}

/* Allocate and return a new buffer of length size bytes. The initial contents
   of the buffer are undefined.

   If pointerful, then the buffer may contain pointers. Otherwise, the caller
   guarantees no pointers will ever be stored in the buffer. This allows
   garbage collection optimizations. If unsure, say true. */
void *ch_malloc(size_t size, bool pointerful)
{
   void *buf;

#ifdef HAVE_GC
   #error
#else
   (void)pointerful;  // suppress warning
   T_ (buf = malloc(size));
#endif

   return buf;
}

/* Initialize memory management.

   We don’t log usage here because it’s called before logging is up. */
void ch_memory_init(void)
{
}

/* Log stack and heap memory usage, and GC statistics if enabled, to stderr
   and syslog if enabled. */
void ch_memory_log(const char *when)
{
   FILE *fp;
   char *line = NULL;
   ssize_t stack_len = 0, heap_len = 0;
   char *text;

   /* Compute stack and heap size. While awkward, AFAICT this is the best
      available way to get these sizes. See proc_pid_maps(5).
      Whitespace-separated (?) fields:

        1. start (inclusive) and end (exclusive) addresses, in hex
        2. permissions, e.g. “r-xp”
        3. offset, in hex
        4. device major:minor, in hex?
        5. inode number, in decimal
        6. pathname */
   T_ (fp = fopen("/proc/self/maps", "r"));
   while ((line = ch_getdelim(fp, '\n'))) {
      int conv_ct;
      void *start, *end;
      char path[8] = { 0 };  // length must match format string!
      conv_ct = sscanf(line, "%p-%p %*[rwxp-] %*x %*x:%*x %*u %7s",
                       &start, &end, path);
      if (conv_ct < 2) {     // will be 2 if path empty
         WARNING("please report this bug: can't parse map: %d: \"%s\"",
                 conv_ct, line);
         break;
      }
      if (!strcmp(path, "[stack]"))
         stack_len += end - start;
      else if (!strcmp(path, "[heap]"))
         heap_len += end - start;
   }
   Z_ (fclose(fp));

   // log the basics
   text = ch_asprintf("mem: %s: stack %zd kB %+zd, heap %zd kB %+zd", when,
                      stack_len / 1024, (stack_len - stack_prev) / 1024,
                      heap_len / 1024, (heap_len - heap_prev) / 1024);
   VERBOSE(text);
#ifdef ENABLE_SYSLOG
   syslog(SYSLOG_PRI, "%s", text);
#endif
   stack_prev = stack_len;
   heap_prev = heap_len;

   // log GC stuff
#ifdef HAVE_GC
   FIXME
#endif
}

void ch_memory_log_exit(void)
{
   ch_memory_log("exit");
}

/* Change the size of allocated buffer p to size bytes. Like realloc(3), if p
   is NULL, then this function is equivalent to ch_malloc(). Unlike free(3),
   size may not be zero.

   If size is greater than the existing buffer length, the initial content of
   new bytes is undefined. If size is less than the existing buffer length,
   this function may be a no-op; i.e., it may be impossible to shrink a
   buffer’s actual allocation.

   pointerful is as in ch_malloc(). If p is non-NULL, it must match the the
   original allocation, though this is not validated. */
void *ch_realloc(void *p, size_t size, bool pointerful)
{
   void *p_new;

#ifdef HAVE_GC
   #error
#else
   (void)pointerful;  // suppress warning
   T_ (p_new = realloc(p, size));
#endif

   return p_new;
}
