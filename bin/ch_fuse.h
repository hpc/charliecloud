/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <stdbool.h>

/** Types **/

/** Function prototypes **/

void fuse_loop_init();
bool sqfs_p(const char *path);
void sqfs_clean();
char *sqfs_mount(char *mountdir, char *filepath);
