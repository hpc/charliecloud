/* Copyright © Triad National Security, LLC, and others.

   This interface contains the seccomp filter for root emulation. */

#define _GNU_SOURCE
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "core.h"
#include "hook.h"


/** Macros **/

/* On some distros (e.g., CentOS 7), some of the architecture numbers are
   missing. The workaround is to use the numbers I have on Debian Bullseye.
   The reason I (Reid) feel moderately comfortable doing this is how militant
   Linux is about not changing the userspace API. */
#ifndef AUDIT_ARCH_AARCH64
#define AUDIT_ARCH_AARCH64 0xC00000B7u  // undeclared on CentOS 7
#undef  AUDIT_ARCH_ARM                  // uses undeclared EM_ARM on CentOS 7
#define AUDIT_ARCH_ARM     0x40000028u
#endif

/* Special values for seccomp tables. These must be negative to avoid clashing
   with real syscall numbers (note zero is often a valid syscal number). */
#define NR_NON -1  // syscall does not exist on architecture
#define NR_END -2  // end of table

/** Constants **/

/* Architectures we support for seccomp. Order matches the table below. */
int SECCOMP_ARCHS[] = { AUDIT_ARCH_AARCH64,   // arm64
                        AUDIT_ARCH_ARM,       // arm32
                        AUDIT_ARCH_I386,      // x86 (32-bit)
                        AUDIT_ARCH_PPC64LE,   // PPC
                        AUDIT_ARCH_S390X,     // s390x
                        AUDIT_ARCH_X86_64,    // x86-64
                        NR_END };

/* System call numbers that we fake with seccomp (by doing nothing and
   returning success). Some processors can execute multiple architectures
   (e.g., 64-bit Intel CPUs can run both x64-64 and x86 code), and a process’
   architecture can even change (if you execve(2) binary of different
   architecture), so we can’t just use the build host’s architecture.

   I haven’t figured out how to gather these system call numbers
   automatically, so they are compiled from [1, 2, 3]. See also [4] for a more
   general reference.

   NOTE: The total number of faked syscalls (i.e., non-zero entries below)
   must be somewhat less than 256. I haven’t computed the exact limit. There
   will be an assertion failure at runtime if this is exceeded.

   WARNING: Keep this list consistent with the ch-image(1) man page!

   [1]: https://chromium.googlesource.com/chromiumos/docs/+/HEAD/constants/syscalls.md#Cross_arch-Numbers
   [2]: https://github.com/strace/strace/blob/v4.26/linux/powerpc64/syscallent.h
   [3]: https://github.com/strace/strace/blob/v6.6/src/linux/s390x/syscallent.h
   [4]: https://unix.stackexchange.com/questions/421750 */
int FAKE_SYSCALL_NRS[][6] = {
   // arm64   arm32   x86     PPC64   s390x   x86-64
   // ------  ------  ------  ------  ------  ------
   {      91,    185,    185,    184,    185,    126 },  // capset
   {  NR_NON,    182,    182,    181,    212,     92 },  // chown
   {  NR_NON,    212,    212, NR_NON, NR_NON, NR_NON },  // chown32
   {      55,     95,     95,     95,    207,     93 },  // fchown
   {  NR_NON,    207,    207, NR_NON, NR_NON, NR_NON },  // fchown32
   {      54,    325,    298,    289,    291,    260 },  // fchownat
   {  NR_NON,     16,     16,     16,    198,     94 },  // lchown
   {  NR_NON,    198,    198, NR_NON, NR_NON, NR_NON },  // lchown32
   {     104,    347,    283,    268,    277,    246 },  // kexec_load
   {     152,    139,    139,    139,    216,    123 },  // setfsgid
   {  NR_NON,    216,    216, NR_NON, NR_NON, NR_NON },  // setfsgid32
   {     151,    138,    138,    138,    215,    122 },  // setfsuid
   {  NR_NON,    215,    215, NR_NON, NR_NON, NR_NON },  // setfsuid32
   {     144,     46,     46,     46,    214,    106 },  // setgid
   {  NR_NON,    214,    214, NR_NON, NR_NON, NR_NON },  // setgid32
   {     159,     81,     81,     81,    206,    116 },  // setgroups
   {  NR_NON,    206,    206, NR_NON, NR_NON, NR_NON },  // setgroups32
   {     143,     71,     71,     71,    204,    114 },  // setregid
   {  NR_NON,    204,    204, NR_NON, NR_NON, NR_NON },  // setregid32
   {     149,    170,    170,    169,    210,    119 },  // setresgid
   {  NR_NON,    210,    210, NR_NON, NR_NON, NR_NON },  // setresgid32
   {     147,    164,    164,    164,    208,    117 },  // setresuid
   {  NR_NON,    208,    208, NR_NON, NR_NON, NR_NON },  // setresuid32
   {     145,     70,     70,     70,    203,    113 },  // setreuid
   {  NR_NON,    203,    203, NR_NON, NR_NON, NR_NON },  // setreuid32
   {     146,     23,     23,     23,    213,    105 },  // setuid
   {  NR_NON,    213,    213, NR_NON, NR_NON, NR_NON },  // setuid32
   { NR_END }, // end
};
int FAKE_MKNOD_NRS[] =
   {  NR_NON,     14,     14,     14,     14,    133 };
int FAKE_MKNODAT_NRS[] =
   {      33,    324,    297,    288,    290,    259 };


/** Function prototypes (private) **/

void iw(struct sock_fprog *p, int i,
        uint16_t op, uint32_t k, uint8_t jt, uint8_t jf);


/** Functions **/

/* Prestart hook to set up the fake-syscall seccomp(2) filter. This computes
   and installs a long-ish but fairly simple BPF program to implement the
   filter. To understand this rather hairy language:

     1. https://man7.org/training/download/secisol_seccomp_slides.pdf
     2. https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html
     3. https://elixir.bootlin.com/linux/latest/source/samples/seccomp */
void hook_seccomp_install(struct container *c, void *d)
{
   int arch_ct = sizeof(SECCOMP_ARCHS)/sizeof(SECCOMP_ARCHS[0]) - 1;
   int syscall_cts[arch_ct];
   struct sock_fprog p = { 0 };
   int ii, idx_allow, idx_fake, idx_mknod, idx_mknodat, idx_next_arch;
   // Lengths of certain instruction groups. These are all obtained manually
   // by counting below, violating DRY. We could automate these counts, but it
   // seemed like the cost of extra buffers and code to do that would exceed
   // that of maintaining the manual counts.
   int ct_jump_start = 4;  // ld arch & syscall nr, arch test, end-of-arch jump
   int ct_mknod_jump = 2;  // jump table handling for mknod(2) and mknodat(2)
   int ct_mknod = 2;       // mknod(2) handling
   int ct_mknodat = 6;     // mknodat(2) handling

   // Count how many syscalls we are going to fake in the standard way. We
   // need this to compute the right offsets for all the jumps.
   for (int ai = 0; SECCOMP_ARCHS[ai] != NR_END; ai++) {
      p.len += ct_jump_start + ct_mknod_jump;
      syscall_cts[ai] = 0;
      for (int si = 0; FAKE_SYSCALL_NRS[si][0] != NR_END; si++) {
         bool syscall_p = FAKE_SYSCALL_NRS[si][ai] != NR_NON;
         syscall_cts[ai] += syscall_p;
         p.len += syscall_p;  // syscall jump table entry
      }
   }

   // Initialize program buffer.
   p.len += (  1             // return allow
             + 1             // return fake success
             + ct_mknod      // mknod(2) handling
             + ct_mknodat);  // mknodat(2) handling
   DEBUG("seccomp: filter program has %d instructions", p.len);
   T_ (p.filter = calloc(p.len, sizeof(struct sock_filter)));

   // Return call addresses. Allow needs to come first because we’ll jump to
   // it for unknown architectures.
   idx_allow =   p.len - 2 - ct_mknod - ct_mknodat;
   idx_fake =    p.len - 1 - ct_mknod - ct_mknodat;
   idx_mknod =   p.len     - ct_mknod - ct_mknodat;
   idx_mknodat = p.len                - ct_mknodat;

   // Build a jump table for each architecture. The gist is: if architecture
   // matches, fall through into the jump table, otherwise jump to the next
   // architecture (or ALLOW for the last architecture).
   ii = 0;
   idx_next_arch = -1;  // avoid warning on some compilers
   for (int ai = 0; SECCOMP_ARCHS[ai] != NR_END; ai++) {
      int jump;
      idx_next_arch = ii + syscall_cts[ai] + ct_jump_start + ct_mknod_jump;
      // load arch into accumulator
      iw(&p, ii++, BPF_LD|BPF_W|BPF_ABS,
         offsetof(struct seccomp_data, arch), 0, 0);
      // jump to next arch if arch doesn't match
      jump = idx_next_arch - ii - 1;
      T_ (jump <= 255);
      iw(&p, ii++, BPF_JMP|BPF_JEQ|BPF_K, SECCOMP_ARCHS[ai], 0, jump);
      // load syscall number into accumulator
      iw(&p, ii++, BPF_LD|BPF_W|BPF_ABS,
         offsetof(struct seccomp_data, nr), 0, 0);
      // jump table of syscalls
      for (int si = 0; FAKE_SYSCALL_NRS[si][0] != NR_END; si++) {
         int nr = FAKE_SYSCALL_NRS[si][ai];
         if (nr != NR_NON) {
            jump = idx_fake - ii - 1;
            T_ (jump <= 255);
            iw(&p, ii++, BPF_JMP|BPF_JEQ|BPF_K, nr, jump, 0);
         }
      }
      // jump to mknod(2) handling (add even if syscall not implemented to
      // make the instruction counts simpler)
      jump = idx_mknod - ii - 1;
      T_ (jump <= 255);
      iw(&p, ii++, BPF_JMP|BPF_JEQ|BPF_K, FAKE_MKNOD_NRS[ai], jump, 0);
      // jump to mknodat(2) handling
      jump = idx_mknodat - ii - 1;
      T_ (jump <= 255);
      iw(&p, ii++, BPF_JMP|BPF_JEQ|BPF_K, FAKE_MKNODAT_NRS[ai], jump, 0);
      // unfiltered syscall, jump to allow (limit of 255 doesn’t apply to JA)
      jump = idx_allow - ii - 1;
      iw(&p, ii++, BPF_JMP|BPF_JA, jump, 0, 0);
   }
   T_ (idx_next_arch == idx_allow);

   // Returns. (Note that if we wanted a non-zero errno, we’d bitwise-or with
   // SECCOMP_RET_ERRNO. But because fake success is errno == 0, we don’t need
   // a no-op “| 0”.)
   T_ (ii == idx_allow);
   iw(&p, ii++, BPF_RET|BPF_K, SECCOMP_RET_ALLOW, 0, 0);
   T_ (ii == idx_fake);
   iw(&p, ii++, BPF_RET|BPF_K, SECCOMP_RET_ERRNO, 0, 0);

   // mknod(2) handling. This just loads the file mode and jumps to the right
   // place in the mknodat(2) handling.
   T_ (ii == idx_mknod);
   // load mode argument into accumulator
   iw(&p, ii++, BPF_LD|BPF_W|BPF_ABS,
                offsetof(struct seccomp_data, args[1]), 0, 0);
   // jump to mode test
   iw(&p, ii++, BPF_JMP|BPF_JA, 1, 0, 0);

   // mknodat(2) handling.
   T_ (ii == idx_mknodat);
   // load mode argument into accumulator
   iw(&p, ii++, BPF_LD|BPF_W|BPF_ABS,
                offsetof(struct seccomp_data, args[2]), 0, 0);
   // jump to fake return if trying to create a device.
   iw(&p, ii++, BPF_ALU|BPF_AND|BPF_K, S_IFMT, 0, 0);   // file type only
   iw(&p, ii++, BPF_JMP|BPF_JEQ|BPF_K, S_IFCHR, 2, 0);
   iw(&p, ii++, BPF_JMP|BPF_JEQ|BPF_K, S_IFBLK, 1, 0);
   // returns
   iw(&p, ii++, BPF_RET|BPF_K, SECCOMP_RET_ALLOW, 0, 0);
   iw(&p, ii++, BPF_RET|BPF_K, SECCOMP_RET_ERRNO, 0, 0);

   // Install filter. Use prctl(2) rather than seccomp(2) for slightly greater
   // compatibility (Linux 3.5 rather than 3.17) and because there is a glibc
   // wrapper.
   T_ (ii == p.len);  // next instruction now one past the end of the buffer
   Z_ (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &p));
   DEBUG("seccomp: see contributor's guide to disassemble")

   // Test filter. This will fail if the kernel executes the call (because we
   // are not really privileged and the arguments are bogus) or succeed if
   // filter handles it. We selected it over something more naturally in the
   // filter, e.g. setuid(2), because (1) no container process should ever use
   // it and (2) it’s unlikely to be emulated by a smarter filter in the
   // future, i.e., it won’t silently start doing something.
   Zf (syscall(SYS_kexec_load, 0, 0, NULL, 0),
       "seccomp root emulation failed (is your architecture supported?)");
}

/* Helper function to write seccomp-bpf programs. */
void iw(struct sock_fprog *p, int i,
        uint16_t op, uint32_t k, uint8_t jt, uint8_t jf)
{
   p->filter[i] = (struct sock_filter){ op, jt, jf, k };
}

