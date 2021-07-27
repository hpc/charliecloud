/* Copyright © Triad National Security, LLC, and others. */

/* There are different prefixs depending on where the function is from.
   squashFUSE uses the prefix sqfs_ll for lowlevel functionality. Charliecloud
   used the prefix sq. */

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

/* Holds fuse low level operations */
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
   char *mountpt;       // mount point of sqfs
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
   DEBUG("unmounting: %s", sq.mountpt);
   sqfs_ll_unmount(&sq.chan, sq.mountpt);
}

/* Returns if image a directory, sqfs or others */
enum img img_type(const char *path)
{
   struct stat read;
   FILE *file;
   char magic[4];

   Te (stat(path, &read) == 0, "can't stat %s", path);
   if (S_ISDIR(read.st_mode)) // is a dir?
      return DIRECTORY;

   if (!S_ISREG(read.st_mode)) // not a file?
      return OTHER;

   file = fopen(path, "rb");
   Te ((file != NULL), "can't open %s", path);
   Te ((fread(magic, 4, 1, file) == 1), "can't read %s", path);

   // sqfs magic number: 0x73717368
   // see: https://dr-emann.github.io/squashfs/
   DEBUG("Magic Number: %x%x%x%x", magic[3], magic[2], magic[1], magic[0]);
   if(strcmp(magic, "hsqs") == 0) // is a sqfs?
      return SQFS;
   return OTHER;
}

/* Mounts sqfs image. Returns mount point */
void sq_mount(char *mountdir, char *filepath)
{
   // argc set at 2 when verbose set to 3+ which sets debug argument for FUSE
   char *argv[] = {filepath, "-d"};
   int argc = (verbose > 2) ? 2 : 1;
   struct fuse_args args = FUSE_ARGS_INIT(argc, argv); //arguments for FUSE

   sq.mountpt = mountdir;
   INFO("mount point: %s", sq.mountpt);

   // mount sqfs
   sq.ll = sqfs_ll_open(filepath, 0);
   Te (sq.ll, "failed to open %s", filepath);
   if(!opendir(sq.mountpt)) {
      Tf ((ENOENT == errno), "can't make %s", sq.mountpt); //errno not dir doesn't exist
      Ze (mkdir(sq.mountpt, 0777), "failed to make: %s", sq.mountpt);
   }

   // two 'sources' of error 1. can't create fuse session, 2. can't mount
   if (SQFS_OK != sqfs_ll_mount(&sq.chan, sq.mountpt, &args, &sqfs_ll_ops, sizeof(sqfs_ll_ops), sq.ll)) {
      Te ((sq.chan.session), "failed to make fuse session");
      FATAL("failed to mount");
   }
   signal(SIGCHLD, sq_end); //end fuse loop when ch-run is done

   // tries to set signal handlers, returns -1 if failed
   Te ((fuse_set_signal_handlers(sq.chan.session) >= 0), "can't set signal handlers");

   // child process never returns when successful
   // parent process runs fuse loop until child process ends and sends a SIGCHLD
   int status = fork();
   Te (status >=0, "failed to fork process");
   if (status > 0) { //parent process
      // tries to create fuse loop, returns -1 if failed
      Te ((fuse_session_loop(sq.chan.session) >= 0), "failed to make fuse loop");
   }
}
