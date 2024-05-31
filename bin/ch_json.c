/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE

#include "config.h"

#include CJSON_H

#include "ch_json.h"
#include "ch_misc.h"


/** Macros **/


/** Constants **/


/** Global variables **/


/** Function prototypes (private) **/


/** Functions **/

/* Update container configuration c according to CDI arguments given. Note
   that here we just tidy up the configuration. Actually doing things (e.g.
   bind mounts) happens later. */
void cdi_update(struct container *c, char **devids)
{
   // read CDI spec files in configured directories

   // read CDI spec files specifically requested

   // filter device kinds to those requested

   // figure out bind mounts actually needed and set up symlinks

   // set ldconfig bit

   for (size_t i = 0; devids[i] != NULL; i++) {
      VERBOSE("CDI device request %d: %s", i, devids[i]);
   }
}
