/* Copyright © Triad National Security, LLC, and others.
   This interface contains Charliecloud's core containerization features. */

#define _GNU_SOURCE
#include <stdbool.h>

 /** Types **/
/*struct squash {
   char *filepath;             // path of sqfs file
   char *mountdir;             // location where squashfs is mounted
   pid_t pid;                  // process id of the fuse loop
   struct sqfs_ll_chan *chan;  // fuse channel associated with squash fuse session
   sqfs_ll *ll;                // sqfs_ll data
};*/

/** Function prototypes **/

bool sqfs_ll_check(const char *path, size_t offset);
void sqfs_run_user_command(char *argv[], const char *inital_dir);
char *sqfs_mount(char *mountdir, char *filepath);
