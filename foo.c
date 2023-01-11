/* Run with: $ gcc -Wall -Werror -std=c99 -fmax-errors=1 foo.c && ./a.out */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <linux/unistd.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <unistd.h>


#define T_(x)  if (!(x)) msg_fatal(__FILE__, __LINE__, errno, NULL)
#define Z_(x)  if (x)    msg_fatal(__FILE__, __LINE__, errno, NULL)


void msg_fatal(const char *file, int line, int errno_,
                        const char *fmt, ...)
{
   va_list ap;

   fprintf(stderr, "FATAL");

   va_start(ap, fmt);

   vfprintf(stderr, fmt, ap);
   if (errno_)
      fprintf(stderr, ": %s (%s:%d %d)\n",
              strerror(errno_), file, line, errno_);
   else
      fprintf(stderr, " (%s:%d)\n", file, line);
   if (fflush(stderr))
      abort();  // can't print an error b/c already trying to do that

   va_end(ap);

   exit(EXIT_FAILURE);
}

int main(int argc, char **argv)
{
   int fd;
   struct stat st;

   // BPF program
   // https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html
   // https://elixir.bootlin.com/linux/latest/source/include/uapi/asm-generic/unistd.h
   // https://elixir.bootlin.com/linux/latest/source/samples/seccomp
   // https://man7.org/training/download/secisol_seccomp_slides.pdf
   // https://unix.stackexchange.com/questions/421750
   // https://chromium.googlesource.com/chromiumos/docs/+/HEAD/constants/syscalls.md
   struct sock_filter filter[] = {
      // FIXME: arch-check code

      // 1. Load syscall number into accumulator.
      BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),

      // 2. If it’s one of these syscalls (i.e., syscall number equals
      //    accumulator), jump ahead to the bypass. WARNING: Because the jump
      //    destinations are an instruction count, not a label, double-check
      //    all these addresses if you make any changes.
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_fchmod, 1, 0),

      // 3. Run syscall unchanged (default).
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),

      // 4. Skip syscall, and just return success, i.e. errno == 0. (If we
      // wanted any non-zero errno, we’d bitwise-or with SECCOMP_RET_ERRNO.)
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO),
   };
   struct sock_fprog prog = {
      .len = (unsigned short)(sizeof(filter)/sizeof(filter[0])),
      .filter = filter,
   };

   // create file if needed
   T_ ((fd = open("foo", O_CREAT|O_RDONLY)) > 0);

   // chmod it to known state
   Z_ (fchmod(fd, 0444));

   // stat, report
   Z_ (fstat(fd, &st));
   printf("starting mode: %o\n", st.st_mode);

   // install filter
   Z_ (prctl(PR_SET_NO_NEW_PRIVS, 1));
   Z_ (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog));

   // chmod again -- this should succeed but have no effect
   printf("chmod to 0600\n");
   Z_ (fchmod(fd, 0600));

   // stat, report
   Z_ (fstat(fd, &st));
   printf("ending mode: %o\n", st.st_mode);

   // close file
   Z_ (close(fd));

   return 0;
}
