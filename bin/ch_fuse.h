/* Copyright © Triad National Security, LLC, and others.
   This interface contains Charliecloud's core containerization features. */

#define _GNU_SOURCE
#include <stdbool.h>

 /** Types **/
struct squash {
   char *filepath;        // path of sqfs file
   char *mountdir;        //location where squashfs is mounted
   pid_t pid;             // process id of the fuse loop
   struct fuse_chan *ch;  //fuse channel associated with squash fuse session
   struct fuse *fuse;     //fuse struct associated with squash fuse session
   char *parentdir;       //location of mountpoint parent directory
};

/** Function prototypes **/

void sqfs_run_user_command(char *argv[], const char *inital_dir);
char *sqfs_mount(char *mountdir, char *filepath);
