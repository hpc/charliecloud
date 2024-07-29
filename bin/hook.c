/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <stdlib.h>


#include "core.h"
#include "hook.h"
#include "misc.h"


/** Function prototypes (private) **/


/** Functions **/

/* Set the environment variables listed in d, then free d. */
void hook_envs_set(struct container *c, void *d)
{
   struct env_var *vars = d;

   envs_set(vars, c->env_expand);
   envs_free(&vars);
}

/* Set the environment variables specified in file d, then free d. NOTE:
   d->path is still owned by hook_envs_install()’s caller, so we do not free
   that buffer. */
void hook_envs_set_file(struct container *c, void *d)
{
   struct env_file *ef = d;
   struct env_var *vars = env_file_read(ef->path, ef->delim);

   envs_set(vars, c->env_expand);
   envs_free(&vars);
   free(ef);
}

/* Unset the environment variables matching glob d. NOTE: d is owned by
   hook_envs_install()’s caller, so we do not free it. */
void hook_envs_unset(struct container *c, void *d)
{
   envs_unset((char *)d);
}


void hook_ldconfig(struct container *c, void *d)
{
}
