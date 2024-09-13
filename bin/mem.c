/* libgc API
   ---------

   See:

     https://hboehm.info/gc/gcinterface.html
     https://github.com/ivmai/bdwgc/blob/57ccbcc/include/gc/gc.h#L459

   The latter is more complete.

   libgc provides both upper-case, e.g. GC_MALLOC(), and lower-case, e.g.
   GC_malloc(), versions of many functions. It’s not totally clear to me what
   the separation principles are, though the vibe does seem to prefer the
   upper-case versions. We use the upper-case when available.

   Zeroing newly-allocated memory
   ------------------------------

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
#include "config.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>

#ifdef HAVE_GC
#include <gc.h>
#endif

#include "mem.h"
#include "misc.h"


/** Macros **/

/** Types **/

/** Constants **/

/** Function prototytpes (private) **/

ssize_t kB(ssize_t byte_ct);


/** Globals **/

/* Note: All the memory statistics are signed “ssize_t” rather than the more
   correct unsigned “size_t” so that subtractions are less error-prone (we
   report lots of differences). We assume that memory usage is small enough
   for this to not matter. */

/* Size of the stack, heap, and anonymous mmap(2) mappings at previous
   ch_memory_log() call. */
ssize_t stack_prev = 0;
ssize_t heap_prev = 0;
ssize_t anon_prev = 0;

#ifdef HAVE_GC

/* Note: The first four counters are from GC_prof_stats_s fields and have the
   corresponding names. Total size of allocated blocks is derived. See gc.h. */

/* Total size of the heap. This includes “unmapped” bytes that libgc is
   tracking but has given back to the OS, I assume to be re-requested from the
   OS if needed. */
ssize_t heapsize_prev = 0;

/* Free bytes in the heap, both mapped and unmapped. */
ssize_t free_prev = 0;

/* Unmapped bytes (i.e., returned to the OS but still tracked by libgc) in the
   heap. */
ssize_t unmapped_prev = 0;

/* Number of garbage collections done so far. */
ssize_t gc_no_prev = 0;

/* Total time spent doing garbage collection, in milliseconds. Corresponds to
   GC_get_full_gc_total_time(). Note that because ch-run is single-threaded,
   we do not report time spent collecting with the world stopped. */
long time_collecting_prev = 0;

#endif


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
   buf = pointerful ? GC_MALLOC(size) : GC_MALLOC_ATOMIC(size);
#else
   (void)pointerful;  // suppress warning
   buf = malloc(size);
#endif

   T_ (buf);
   return buf;
}

/* Shut down memory management. */
void ch_memory_exit(void)
{
   ch_memory_log("exit");
}

/* Initialize memory management. We don’t log usage here because it’s called
   before logging is up. */
void ch_memory_init(void)
{
#ifdef HAVE_GC
   //GC_set_handle_fork(1); // I think the default mode is fine???
   GC_INIT();
   GC_start_performance_measurement();
#endif
}

/* Log stack and heap memory usage, and GC statistics if enabled, to stderr
   and syslog if enabled. */
void ch_memory_log(const char *when)
{
   FILE *fp;
   char *line = NULL;
   char *s;
   ssize_t stack_len = 0, heap_len = 0, anon_len = 0;
#ifdef HAVE_GC
   struct GC_prof_stats_s ps;
   ssize_t alloc, alloc_prev;
   long time_collecting;
#endif

   /* Compute stack, heap, and anonymous mapping sizes. While awkward, AFAICT
      this is the best available way to get these sizes. See proc_pid_maps(5).
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
      if (strlen(path) == 0)
         anon_len += end - start;
      else if (!strcmp(path, "[stack]"))
         stack_len += end - start;
      else if (!strcmp(path, "[heap]"))
         heap_len += end - start;
   }
   Z_ (fclose(fp));

   // log the basics
   s = ch_asprintf("mem: %s: "
         "stac %zdkB %+zd, heap %zdkB %+zd, anon %zdkB %+zd",
         when,
         kB(stack_len), kB(stack_len - stack_prev),
         kB(heap_len),  kB(heap_len - heap_prev),
         kB(anon_len),  kB(anon_len - anon_prev));
   DEBUG(s);
#ifdef ENABLE_SYSLOG
   syslog(SYSLOG_PRI, "%s", s);
#endif
   stack_prev = stack_len;
   heap_prev = heap_len;
   anon_prev = anon_len;

   // log GC stuff
#ifdef HAVE_GC
   GC_get_prof_stats(&ps, sizeof(ps));
   time_collecting = GC_get_full_gc_total_time();
   alloc = ps.heapsize_full - ps.free_bytes_full;
   alloc_prev = heapsize_prev - free_prev;
   s = ch_asprintf("gc:  "
         "%s: %ld collections (%+ld) in %zdms (%+zd)",
         when,
         ps.gc_no, ps.gc_no - gc_no_prev,
         time_collecting, time_collecting - time_collecting_prev);
   DEBUG(s);
#ifdef ENABLE_SYSLOG
   syslog(SYSLOG_PRI, "%s", s);
#endif
   gc_no_prev = ps.gc_no;
   time_collecting_prev = time_collecting;
   s = ch_asprintf("gc:  %s: "
         "totl %zdkB %+zd, allc %zdkB %+zd, free %zdkB %+zd, unmp %zdkB %+zd",
         when,
         kB(ps.heapsize_full), kB(ps.heapsize_full - heapsize_prev),
         kB(alloc), kB(alloc - alloc_prev),
         kB(ps.free_bytes_full), kB(ps.free_bytes_full - free_prev),
         kB(ps.unmapped_bytes), kB(ps.unmapped_bytes - unmapped_prev));
   DEBUG(s);
#ifdef ENABLE_SYSLOG
   syslog(SYSLOG_PRI, "%s", s);
#endif
   heapsize_prev = ps.heapsize_full;
   free_prev = ps.free_bytes_full;
   unmapped_prev = ps.unmapped_bytes;
#endif
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

   T_ (size > 0);

   if (p == NULL)
      p_new = ch_malloc(size, pointerful);  // no GC_REALLOC_ATOMIC()
   else {
#ifdef HAVE_GC
      p_new = GC_REALLOC(p, size);
#else
      p_new = realloc(p, size);
#endif
   }

   T_ (p_new);
   return p_new;
}

/* Convert a signed number of bytes to kilobytes (truncated) and return it. */
ssize_t kB(ssize_t byte_ct)
{
   return byte_ct / 1024;
}

