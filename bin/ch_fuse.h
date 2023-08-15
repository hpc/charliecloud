/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <squashfuse/ll.h>

/** Function prototypes **/

void sq_fork(struct container *c);
sqfs_ll *sqfs_ll_open_(const char *path, size_t offset);
