/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/wait.h>

// low level functionality from squashfuse
#include <ll.h>

#include "ch_fuse.h"
#include "ch_core.h"
#include "ch_misc.h"

/** Macros **/

/** Types **/
struct squash {
   char *mountdir;      // mount point of sqfs
   pid_t pid;           // PID of fuse loop
   sqfs_ll_chan chan;   // fuse channel associated with squash fuse session
   sqfs_ll *ll;         // squashfs image
};


/** Global variables **/
struct squash sq;

/** Function prototypes (private) **/
void get_fuse_ops(struct fuse_lowlevel_ops *sqfs_ll_ops);
void fuse_end();

/** Functions **/

/* Initalize fuse loop */
void fuse_loop_init()
{
   // tries to set signal handlers, returns -1 if failed
   Te((fuse_set_signal_handlers(sq.chan.session) >= 0), "can't set signal handlers");
   if ((fork()) != 0) { //parent process
      sq.pid = getpid();
      // tries to create fuse loop, returns -1 if failed
      Te((fuse_session_loop(sq.chan.session) >= 0), "failed to create fuse loop");
   }
}

/* Starts sqfs_ll_clean by exiting out of final process */
void fuse_end()
{
   DEBUG("end fuse loop: %d", sq.pid);
   exit(0);
}

/* Ends fuse loop and unmounts sqfs */
void sqfs_clean()
{
   fuse_remove_signal_handlers(sq.chan.session);
   sqfs_ll_destroy(sq.ll);
   DEBUG("unmounting: %s", sq.mountdir);
   sqfs_ll_unmount(&sq.chan, sq.mountdir);
}

/* Returns true if path is a sqfs */
bool sqfs_p(const char *path)
{
   sqfs_ll *ll;
   sqfs_fd_t fd;

   ll = malloc(sizeof(*ll));
   Tf (ll, "can't allocate memory");
   memset(ll, 0 , sizeof(*ll));
   fd = open(path, O_RDONLY);
   if(fd != -1 && sqfs_init(&ll->fs, fd, 0) == SQFS_OK)
      return true;
   sqfs_destroy(&ll->fs);
   free(ll);
   return false;
}

/* Mounts sqfs image. Returns mount point */
char *sqfs_mount(char *mountdir, char *filepath)
{
   sq.mountdir = mountdir;
   DEBUG("mount path: %s", sq.mountdir);

   //init fuse,etc.
   struct fuse_args args;
   struct fuse_lowlevel_ops sqfs_ll_ops;
   args.argc = 1;
   args.argv = &filepath;
   args.allocated = 0;
   get_fuse_ops(&sqfs_ll_ops);

   // mount sqfs
   sq.ll = sqfs_ll_open(filepath, 0);
   Te (sq.ll, "%s does not exist", filepath);
   Ze (opendir(sq.mountdir), "%s already exists", sq.mountdir);
   Ze (mkdir(sq.mountdir, 0777), "failed to create: %s", sq.mountdir);
   Te (SQFS_OK == sqfs_ll_mount(&sq.chan, sq.mountdir, &args, &sqfs_ll_ops, sizeof(sqfs_ll_ops), sq.ll), "failed to mount");
   Ze ((sq.chan.session == NULL), "failed to create fuse session");

   signal(SIGCHLD, fuse_end); //end fuse loop when ch-run is done
   fuse_loop_init();
   return sq.mountdir;
}

/* Assign ops to fuse_lowlevel_ops */
void get_fuse_ops(struct fuse_lowlevel_ops *sqfs_ll_ops) {
   memset(sqfs_ll_ops, 0, sizeof(*sqfs_ll_ops));
   (*sqfs_ll_ops).getattr    = &sqfs_ll_op_getattr;
   (*sqfs_ll_ops).opendir    = &sqfs_ll_op_opendir;
   (*sqfs_ll_ops).releasedir = &sqfs_ll_op_releasedir;
   (*sqfs_ll_ops).readdir    = &sqfs_ll_op_readdir;
   (*sqfs_ll_ops).lookup     = &sqfs_ll_op_lookup;
   (*sqfs_ll_ops).open       = &sqfs_ll_op_open;
   (*sqfs_ll_ops).create     = &sqfs_ll_op_create;
   (*sqfs_ll_ops).release    = &sqfs_ll_op_release;
   (*sqfs_ll_ops).read       = &sqfs_ll_op_read;
   (*sqfs_ll_ops).readlink   = &sqfs_ll_op_readlink;
   (*sqfs_ll_ops).listxattr  = &sqfs_ll_op_listxattr;
   (*sqfs_ll_ops).getxattr   = &sqfs_ll_op_getxattr;
   (*sqfs_ll_ops).forget     = &sqfs_ll_op_forget;
   (*sqfs_ll_ops).statfs     = &stfs_ll_op_statfs;

}
