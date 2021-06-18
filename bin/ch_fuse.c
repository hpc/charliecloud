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
   sqfs_ll_chan chan;   //fuse channel associated with squash fuse session
   sqfs_ll *ll;         // tbh no idea
};

/** Constants **/

/** Global variables **/
struct squash sq;

/** Function prototypes (private) **/
void get_fuse_ops(struct fuse_lowlevel_ops *sqfs_ll_ops);



/** Functions **/

void sqfs_ll_clean()
{
   kill(sq.pid, SIGINT);
   fuse_remove_signal_handlers(sq.chan.session);
   sqfs_ll_destroy(sq.ll);
   sqfs_ll_unmount(&sq.chan, sq.mountdir);
}

bool sqfs_ll_check(const char *path, size_t offset)
{
   sqfs_ll *ll;
   sqfs_fd_t fd;

   ll = malloc(sizeof(*ll));
   if (!ll) {
      FATAL("Can't allocate memory");
   } else {
      memset(ll, 0 , sizeof(*ll));
      fd = open(path, O_RDONLY);
      if(fd != -1) {
         if(sqfs_init(&ll->fs, fd, offset) == SQFS_OK)
            return true;
      }
      sqfs_destroy(&ll->fs);
      free(ll);
   }
   return false;
}

void sqfs_run_user_command(char *argv[], const char *initial_dir)
{
   if (initial_dir != NULL)
      Zf (chdir(initial_dir), "can't cd to %s", initial_dir);

   if (verbose >= 3) {
      fprintf(stderr, "argv:");
      for (int i = 0; argv[i] != NULL; i++)
         fprintf(stderr, " \"%s\"", argv[i]);
      fprintf(stderr, "\n");
   }

   Zf (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0), "can't set no_new_privs");
   int status;
   if (fork() == 0) {
      execvp(argv[0], argv);  // only returns if error
      Tf (0, "can't execve(2): %s", argv[0]);
   }
   wait(&status);
   sqfs_ll_clean();

}

char *sqfs_mount(char *mountdir, char *filepath)
{
   //set mountdir to "mountdir/filepath"
   char *filename, *buffer;
   path_split(filepath, &buffer, &filename); //get file name
   split(&filename, &buffer, filename, '.'); //removes first '.'
   sq.mountdir = cat(cat(mountdir, "/"), filename);
   DEBUG("mount path: %s", sq.mountdir);

   //init fuse,etc.
   struct fuse_args args = FUSE_ARGS_INIT(0, NULL);
   args.argc = 1;
   args.argv = &filepath;
   args.allocated = 0;
   struct fuse_lowlevel_ops sqfs_ll_ops;
   get_fuse_ops(&sqfs_ll_ops);

   // mount sqfs
   sq.ll = sqfs_ll_open(filepath, 0);
   Te(sq.ll, "%s does not exist", filepath);
   Ze(opendir(sq.mountdir), "%s already exists", sq.mountdir);
   Ze(mkdir(sq.mountdir, 0777), "failed to create: %s", sq.mountdir);
   Te(SQFS_OK == sqfs_ll_mount(&sq.chan, sq.mountdir, &args, &sqfs_ll_ops, sizeof(sqfs_ll_ops), sq.ll), "failed to mount");
   Ze((sq.chan.session == NULL), "failed to create fuse session");

   // init fuse loop
   Ze((fuse_set_signal_handlers(sq.chan.session) == -1), "failed to set signal handlers");
   if ((sq.pid= fork()) == 0) {
      Ze((fuse_session_loop(sq.chan.session) == -1), "failed to create fuse loop");
      INFO("exited fuse_session");
      exit(0);
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

