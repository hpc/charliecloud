/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <fcntl.h>
#include <grp.h>
#include <libgen.h>
#include <pwd.h>
#include <sched.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

//new libs
#include <dirent.h>
#include <sys/wait.h>
#include <ll.h>

#include "ch_fuse.h"
#include "ch_core.h"
#include "ch_misc.h"

/** Macros **/

/** Constants **/

/** Global variables **/
struct squash sq;

/** Function prototypes (private) **/
void get_fuse_ops(struct fuse_lowlevel_ops *sqfs_ll_ops);

/** Functions **/

void sqfs_run_user_command(char *argv[], const char *inital_dir)
{

}

char *sqfs_mount(char *mountdir, char *filepath)
{

   //set filepath to filepath
   sq.filepath = filepath;

   //set mountdir to "mountdir/filepath"
   char *filename, *buffer;
   path_split(filepath, &buffer, &filename); //get file name
   split(&filename, &buffer, filename, '.'); //removes first '.'
   sq.mountdir = cat(cat(mountdir, "/"), filename);
   DEBUG("mount path: %s", sq.mountdir);

   //init fuse,etc.
   sqfs_ll_chan chan;
   struct fuse_args args = FUSE_ARGS_INIT(0, NULL);
   args.argc = 1;
   args.argv = &filepath;
   args.allocated = 0;
   struct fuse_lowlevel_ops sqfs_ll_ops;
   get_fuse_ops(&sqfs_ll_ops);
   sqfs_ll *ll;

   // idk, ll_main says it needed to daemonize
   while(true) {
      int fd = open("/dev/null", O_RDONLY);
      if (fd == -1)
         break;
      if (fd > 2) {
         close(fd);
         break;
      }

   }

   // mount sqfs
   ll = sqfs_ll_open(sq.filepath, 0);
   Te(ll, "%s does not exist", sq.filepath);
   Ze(opendir(sq.mountdir), "%s already exists", sq.mountdir);
   Ze(mkdir(sq.mountdir, 0777), "failed to create: %s", sq.mountdir);
   sqfs_ll_mount(&chan, sq.mountdir, &args, &sqfs_ll_ops, sizeof(sqfs_ll_ops), ll);

   // init fuse loop
   if (sqfs_ll_daemonize(1) != -1) {
      if (fuse_set_signal_handlers(chan.session) != -1) {
      }
   }
   return sq.mountdir;
}

void get_fuse_ops(struct fuse_lowlevel_ops *sqfs_ll_ops) {
   memset(sqfs_ll_ops, 0, sizeof(*sqfs_ll_ops));
   (*sqfs_ll_ops).getattr    = &sqfs_ll_op_getattr;
   (*sqfs_ll_ops).opendir    = &sqfs_ll_op_opendir;
   (*sqfs_ll_ops).releasedir = &sqfs_ll_op_releasedir;
   (*sqfs_ll_ops).readdir    = &sqfs_ll_op_readdir;
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

