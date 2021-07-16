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

/** Constants **/

/* holds fuse low level operations */
struct fuse_lowlevel_ops sqfs_ll_ops = {
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

/** Types **/
struct squash {
   char *mountdir;      // mount point of sqfs
   sqfs_ll_chan chan;   // fuse channel associated with squash fuse session
   sqfs_ll *ll;         // squashfs image
};


/** Global variables **/
struct squash sq;

/** Function prototypes (private) **/
void sq_end();

/** Functions **/

/* Assigned to SIGCHLD. When child process (ch-run) is done running it sends a
   SIGCHLD which triggers this method that ends the parent process */
void sq_end()
{
   DEBUG("end fuse loop");
   exit(0);
}

/* Assigned as exit handler. When parent process (fuse loop) ends in sq_end,
   it triggers this method that unmounts and cleans up the sqfs */
void sq_clean()
{
   fuse_remove_signal_handlers(sq.chan.session);
   sqfs_ll_destroy(sq.ll);
   DEBUG("unmounting: %s", sq.mountdir);
   sqfs_ll_unmount(&sq.chan, sq.mountdir);
}

/* Returns true if path is a sqfs */
bool imgdir_p(const char *path)
{
   struct stat buffer;
   FILE *file;
   int magic[4], i;

   Te (stat(path, &buffer) == 0, "failed to stat");
   if (!S_ISREG(buffer.st_mode)) //is a file?
      return false;

   file = fopen(path, "rb");
   for(i = 3; i >=0; i --) {
      magic[i] = fgetc(file);
   }

   //sqfs magic number: 0x73717368
   DEBUG("Magic Number: %x%x%x%x", magic[0], magic[1], magic[2], magic[3]);
   if(magic[0] == 0x73 && magic[1] == 0x71 && magic[2] == 0x73 && magic[3] == 0x68)
      return true;

   FATAL("%s invalid input type"); //errors when file but not a sqfs
   return false;
}

/* Mounts sqfs image. Returns mount point */
char *sq_mount(char *mountdir, char *filepath)
{
   Te (mountdir, "mount dir can't be empty");
   Te (filepath, "filepath can't be empty");
   Te (filepath[0] == '/', "%s must be absolute path", filepath);

   sq.mountdir = mountdir;
   DEBUG("mount path: %s", sq.mountdir);

   //init fuse,etc.
   struct fuse_args args; //arguments passed to fuse used for mount
   args.argc = 1;
   args.argv = &filepath;
   args.allocated = 0;

   // mount sqfs
   sq.ll = sqfs_ll_open(filepath, 0);
   Te (sq.ll, "%s does not exist", filepath); //don't think we'll actually ever hit this error ??..
   if (!opendir(sq.mountdir)) //if directory doesn't exist, create it
      Ze (mkdir(sq.mountdir, 0777), "failed to create: %s", sq.mountdir);

   /* two 'sources' of error 1. can't create fuse session, 2. can't mount */
   if (SQFS_OK != sqfs_ll_mount(&sq.chan, sq.mountdir, &args, &sqfs_ll_ops, sizeof(sqfs_ll_ops), sq.ll)) {
      Te ((sq.chan.session), "failed to create fuse session");
      FATAL("failed to mount");
   }
   signal(SIGCHLD, sq_end); //end fuse loop when ch-run is done

   // tries to set signal handlers, returns -1 if failed
   Te ((fuse_set_signal_handlers(sq.chan.session) >= 0), "can't set signal handlers");

   // child process should never return
   // parent process runs fuse loop until child process ends and sends a SIGCHLD
   int status = fork();
   Te (status >=0, "failed to fork process");
   if (status > 0) { //parent process
      // tries to create fuse loop, returns -1 if failed
      Te ((fuse_session_loop(sq.chan.session) >= 0), "failed to create fuse loop");
   }
   return sq.mountdir;
}
