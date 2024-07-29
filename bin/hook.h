/* Copyright © Triad National Security, LLC, and others.

   This interface contains hooks that don’t deserve their own file. */

#define _GNU_SOURCE
#pragma once

#include "core.h"
#include "misc.h"


/** Types **/

struct env_file {
   char *path;
   char delim;
   bool expand;
};


/** Function prototypes **/

void hook_envs_set_file(struct container *c, void *d);
void hook_envs_set(struct container *c, void *d);
void hook_envs_unset(struct container *c, void *d);
