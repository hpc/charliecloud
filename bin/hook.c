/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include "config.h"

#include <stdlib.h>

#include "core.h"
#include "hook.h"
#include "misc.h"


/** Function prototypes (private) **/


/** Functions **/

/* Set the environment variables listed in d. */
void hook_envs_set(struct container *c, void *d)
{
   struct env_var *vars = d;
   envs_set(vars, c->env_expand);
}

/* Set the environment variables specified in file d. */
void hook_envs_set_file(struct container *c, void *d)
{
   struct env_file *ef = d;
   envs_set(env_file_read(ef->path, ef->delim), c->env_expand);
}

/* Unset the environment variables matching glob d. */
void hook_envs_unset(struct container *c, void *d)
{
   envs_unset((char *)d);
}


void hook_ldconfig(struct container *c, void *d)
{
}
