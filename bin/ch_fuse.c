/* Copyright © Triad National Security, LLC, and others. */

/* Function prefixes:

   fuse_     libfuse; docs: https://libfuse.github.io/doxygen/globals.html
   sqfs_ll_  SquashFUSE; no docs but: https://github.com/vasi/squashfuse
   sq_       Charliecloud */

#define _GNU_SOURCE
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

// SquashFUSE has a bug [1] where ll.h includes SquashFUSE's own config.h.
// This clashes with our own config.h, as well as the system headers because
// it defines _POSIX_C_SOURCE. By defining SQFS_CONFIG_H, SquashFUSE's
// config.h skips itself.
// [1]: https://github.com/vasi/squashfuse/issues/65
#define SQFS_CONFIG_H
// But then FUSE_USE_VERSION isn't defined, which makes other parts of ll.h
// puke. Looking at their code, it seems the only values used are 32 (for
// libfuse3) and 26 (for libfuse2), so we can just blindly define it.
#define FUSE_USE_VERSION 32
// SquashFUSE redefines __le16 unless HAVE_LINUX_TYPES_LE16 is defined. We are
// assuming it is defined in <linux/types.h> on your machine.
#define HAVE_LINUX_TYPES_LE16
// The forget operation in libfuse3 takes uint64_t as third parameter,
// while SquashFUSE defaults to unsigned long as used in libfuse2.
// This causes a mess on arches with different size of these types,
// so explicitly switch to the libfuse3 variant.
#define HAVE_FUSE_LL_FORGET_OP_64T
// Now we can include ll.h.
#include <squashfuse/ll.h>

#include "config.h"
#include "ch_core.h"
#include "ch_fuse.h"
#include "ch_misc.h"


/** Types **/

/* A SquashFUSE mount. SquashFUSE allocates ll for us but not chan; use
   pointers for both for consistency. */
struct squash {
   char *mountpt;       // path to mount point
   sqfs_ll_chan *chan;  // FUSE channel associated with SquashFUSE mount
   sqfs_ll *ll;         // SquashFUSE low-level data structure
};


/** Constants **/

/* This mapping tells libfuse what functions implement which FUSE operations.
   It is passed to sqfs_ll_mount(). Why it is not internal to SquashFUSE I
   have no idea. */
struct fuse_lowlevel_ops OPS = {
    .getattr    = &sqfs_ll_op_getattr,
    .opendir    = &sqfs_ll_op_opendir,
    .releasedir = &sqfs_ll_op_releasedir,
    .readdir    = &sqfs_ll_op_readdir,
    .lookup     = &sqfs_ll_op_lookup,
    .open       = &sqfs_ll_op_open,
    .create     = &sqfs_ll_op_create,
    .release    = &sqfs_ll_op_release,
    .read       = &sqfs_ll_op_read,
    .readlink   = &sqfs_ll_op_readlink,
    .listxattr  = &sqfs_ll_op_listxattr,
    .getxattr   = &sqfs_ll_op_getxattr,
    .forget     = &sqfs_ll_op_forget,
    .statfs     = &stfs_ll_op_statfs
};


/** Global variables **/

/* SquashFUSE mount. Initialized in sq_mount() and then used in most of the
   other functions in this file. It's a global because the signal handler
   needs access to it. */
struct squash sq;

/* True if exit request signal handler received SIGCHLD. */
volatile bool sigchld_received;

/* True if any exit request signal has been received. */
volatile bool loop_terminating = false;


/** Function prototypes (private) **/

void sq_done_request(int signum);
int sq_loop();
void sq_mount(const char *img_path, char *mountpt);


/** Functions **/

/* Signal handler to end the FUSE loop. This simply requests FUSE to end its
   loop, causing fuse_session_loop() to exit. */
void sq_done_request(int signum)
{
   if (!loop_terminating) {  // only act on first signal
      loop_terminating = true;
      sigchld_received = (signum == SIGCHLD);
      fuse_session_exit(sq.chan->session);
   }
}

/* Mount SquashFS archive c->img_path on directory c->newroot. If the latter
   is NULL, then mkdir(2) the default mount point and assign its path to
   c->newroot. After mounting, fork; the child returns immediately while the
   parent runs the FUSE loop until the child exits and then exits itself,
   with the same exit code as the child (unless something else went wrong). */
void sq_fork(struct container *c)
{
   pid_t pid_child;
   struct stat st;

   // Default mount point?
   if (c->newroot == NULL) {
      char *subdir;
      T_ (asprintf(&subdir, "/%s.ch/mnt", username) > 0);
      c->newroot = cat("/var/tmp", subdir);
      VERBOSE("using default mount point: %s", c->newroot);
      mkdirs("/var/tmp", subdir, NULL, NULL);
   }

   // Verify mount point exists and is a directory. (SquashFS file path
   // already checked in img_type_get().)
   Zf (stat(c->newroot, &st), "can't stat mount point: %s", c->newroot);
   Te (S_ISDIR(st.st_mode), "not a directory: %s", c->newroot);

   // Mount SquashFS. Use PR_SET_NO_NEW_PRIVS to actively reject running
   // fusermount3(1) setuid, even if it’s installed that way.
   Zf (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0), "can't set no_new_privs");
   sq_mount(c->img_ref, c->newroot);

   // Now that the filesystem is mounted, we can fork without race condition.
   // The child returns to caller and runs the user command. When that exits,
   // the parent gets SIGCHLD.
   pid_child = fork();
   Tf (pid_child >= 0, "can't fork");
   if (pid_child > 0)  // parent (child does nothing here)
      exit(sq_loop());
}

/* Run the squash loop to completion and return the exit code of the user
   command. Warning: This sets up but does not restore signal handlers. */
int sq_loop(void)
{
   struct sigaction fin, ign;
   int looped, exit_code, child_status;
   // Set up signal handlers. Avoid fuse_set_signal_handlers() because we need
   // to catch a different set of signals, letting some be handled by the user
   // command [1]. Use sigaction(2) instead of signal(2) because the latter's
   // man page [2] says “avoid its use” and there are reports of bad
   // interactions with libfuse [3].
   //
   // [1]: https://unix.stackexchange.com/questions/176235
   // [2]: https://man7.org/linux/man-pages/man2/signal.2.html
   // [3]: https://stackoverflow.com/a/8918597
   fin.sa_handler = sq_done_request;
   Z_ (sigemptyset(&fin.sa_mask));  // block no other signals during handling
   fin.sa_flags = SA_NOCLDSTOP;     // only SIGCHLD on child exit
   ign.sa_handler = SIG_IGN;
   Z_ (sigaction(SIGCHLD, &fin, NULL));  // user command exits
   Z_ (sigaction(SIGHUP,  &ign, NULL));  // terminal/session terminated
   Z_ (sigaction(SIGINT,  &ign, NULL));  // Control-C
   Z_ (sigaction(SIGPIPE, &ign, NULL));  // broken pipe; we don't use pipes
   Z_ (sigaction(SIGTERM, &fin, NULL));  // somebody asked us to exit

   // Run the FUSE loop, which services FUSE requests until sq_done_request()
   // is invoked by a signal and tells it to stop, or someone unmounts the
   // filesystem externally with e.g. fusermount(1). Because we don't use
   // fuse_set_signal_handlers(), the return value doesn't contain the signal
   // number that ended the loop, contrary to the documentation.
   //
   // FIXME: this is single-threaded; see issue #1157.
   looped = fuse_session_loop(sq.chan->session);
   if (looped < 0) {
      errno = -looped;  // restore encoded errno so our logging finds it
      Tf (0, "FUSE session failed");
   }
   VERBOSE("FUSE loop terminated successfully");

   // Clean up zombie child if exit signal was SIGCHLD.
   if (!sigchld_received)
      exit_code = ERR_SQUASH;
   else {
      Tf (wait(&child_status) >= 0, "can't wait for child");
      if (WIFEXITED(child_status)) {
         exit_code = WEXITSTATUS(child_status);
         VERBOSE("child terminated normally with exit code %d", exit_code);
      } else {
         // We now know that the child did not exit normally; the two
         // remaining options are (a) killed by signal and (b) stopped [1].
         // Because we didn't call waitpid(2) with WUNTRACED, we don't get
         // notified if the child is stopped [2], so it must have been
         // signaled, and we need not call WIFSIGNALED().
         //
         // [1]: https://codereview.stackexchange.com/a/109349
         // [2]: https://man7.org/linux/man-pages/man2/wait.2.html
         exit_code = 128 + WTERMSIG(child_status);
         VERBOSE("child terminated by signal %d", WTERMSIG(child_status))
      }
   }

   // Clean up SquashFS mount. These functions have no error reporting.
   VERBOSE("unmounting: %s", sq.mountpt);
   sqfs_ll_destroy(sq.ll);
   sqfs_ll_unmount(sq.chan, sq.mountpt);

   VERBOSE("FUSE loop done");
   return exit_code;
}

/* Mount the SquashFS img_path at mountpt. Exit on any errors. */
void sq_mount(const char *img_path, char *mountpt)
{
   // SquashFUSE mount takes basically a command line rather than having a
   // standard library API. It's unclear to me where this command line is
   // documented, but the libfuse docs [1] suggest mount(8).
   // [1]: https://libfuse.github.io/doxygen/fuse-3_810_83_2include_2fuse_8h.html#ad866b0fd4d81bdbf3e737f7273ba4520
   char *mount_argv[] = {"WEIRDAL", "-d"};
   int mount_argc = (verbose > 3) ? 2 : 1;  // include -d if high verbosity
   struct fuse_args mount_args = FUSE_ARGS_INIT(mount_argc, mount_argv);

   sq.mountpt = mountpt;
   T_ (sq.chan = malloc(sizeof(sqfs_ll_chan)));

   sq.ll = sqfs_ll_open(img_path, 0);
   Te (sq.ll != NULL, "can't open SquashFS: %s; try ch-run -vv?", img_path);

   // sqfs_ll_mount() is squirrely for a couple reasons:
   //
   //   1. Error reporting. We get back only SQFS_OK or SQFS_ERR, with no
   //      further detail. Looking at the source code [1], the latter says
   //      either fuse_session_new() or fuse_session_mount() failed, but we
   //      can't tell which, or get any further information about what went
   //      wrong. Hopefully fusermount3 also printed an error message.
   //
   //   2. Race condition. We have been seeing intermittent errors in the test
   //      suite about permission denied accessing the mount point (issue
   //      #1364). I *think* this is because a previous mount on the same
   //      location is not yet cleaned up. For this reason, we have a short
   //      retry loop.
   //
   // [1]: https://github.com/vasi/squashfuse/blob/74f4fe8/ll.c#L399
   for (int i = 5; true; i--)
      if (SQFS_OK == sqfs_ll_mount(sq.chan, sq.mountpt, &mount_args,
                                   &OPS, sizeof(OPS), sq.ll)) {
         break;  // success
      } else if (i <= 0) {
         FATAL(0, "too many FUSE errors; giving up");
      } else {
         WARNING("FUSE error mounting SquashFS; will retry");
         sleep(1);
      }
}
