/* Copyright © Triad National Security, LLC, and others.
   This interface contains Charliecloud's core containerization features. */

#define _GNU_SOURCE
#include <stdbool.h>

/** Types **/

/** Function prototypes **/

bool sqfs_ll_check(const char *path);
void sqfs_ll_clean();
void sqfs_run_user_command(char *argv[], const char *inital_dir);
char *sqfs_mount(char *mountdir, char *filepath);
