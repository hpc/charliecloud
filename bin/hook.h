/* Copyright © Triad National Security, LLC, and others.

   This interface contains hooks that don’t deserve their own file. */

#define _GNU_SOURCE
#pragma once

#include "core.h"
#include "misc.h"


/** Types **/

struct env_file {
   char *path;
   bool expand;
}


/** Function prototypes **/

void hook_env_set_file(struct container *c, void *d);
void hook_env_set(struct container *c, void *d);
void hook_env_unset(struct container *c, void *d);
