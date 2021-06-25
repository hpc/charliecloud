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

/** Types **/
struct squash {
   char *mountdir;      // mount location of sqfs
   pid_t pid;           // ID of fuse loop
   sqfs_ll_chan chan;   // fuse channel associated with squash fuse session
   sqfs_ll *ll;         // squashfs image
};

/** Constants **/

/** Global variables **/
struct squash sq;

/** Function prototypes (private) **/
void get_fuse_ops(struct fuse_lowlevel_ops *sqfs_ll_ops);
void kill_fuse();
/** Functions **/

void fuse_loop_init()
{
   Ze((fuse_set_signal_handlers(sq.chan.session) == -1), "failed to set signal handlers");
   if ((fork()) != 0) { //parent process
      sq.pid = getpid();
      Ze((fuse_session_loop(sq.chan.session) == -1), "failed to create fuse loop");
      exit(0);
   }

}

void kill_fuse()
{
   DEBUG("end fuse loop: %d", sq.pid);
   exit(0);
}



/* Exit handler for sqfs */
void sqfs_ll_clean()
{
   fuse_remove_signal_handlers(sq.chan.session);
   sqfs_ll_destroy(sq.ll);
   DEBUG("unmounting: %s", sq.mountdir);
   sqfs_ll_unmount(&sq.chan, sq.mountdir);
   Ze(rmdir(sq.mountdir) == -1, "unable to remove directory");
}

/* Path is a sqfs*/
bool sqfs_ll_check(const char *path)
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

/* Run user command with an extra process for sqfs */
void sqfs_run_user_command(char *argv[], const char *initial_dir)
{
   int status;
   if (fork() == 0)
      run_user_command(argv, initial_dir);
   wait(&status);
   kill(sq.pid, SIGINT);
   _Exit(0);

}

/* mounts sqfs image */
char *sqfs_mount(char *mountdir, char *filepath)
{
   //set mountdir to "mountdir/filepath"
   char *filename, *buffer;
   path_split(filepath, &buffer, &filename); //get file name
   split(&filename, &buffer, filename, '.'); //removes first '.'
   sq.mountdir = cat(cat(mountdir, "/"), filename);
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
   Te(sq.ll, "%s does not exist", filepath);
   Ze(opendir(sq.mountdir), "%s already exists", sq.mountdir);
   Ze(mkdir(sq.mountdir, 0777), "failed to create: %s", sq.mountdir);
   Te(SQFS_OK == sqfs_ll_mount(&sq.chan, sq.mountdir, &args, &sqfs_ll_ops, sizeof(sqfs_ll_ops), sq.ll), "failed to mount");
   Ze((sq.chan.session == NULL), "failed to create fuse session");

   // init fuse loop
   signal(SIGCHLD, kill_fuse);
   fuse_loop_init();
   return sq.mountdir;
}

/* Assign ops to fuse_lowlevel_ops*/
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

