/* Copyright © Triad National Security, LLC, and others.

   This interface contains all functions that deal with JSON: OCI, CDI, and
   friends. */

#define _GNU_SOURCE
#pragma once

#include <stdbool.h>

#include "config.h"
#include "core.h"
#include "misc.h"

#include CJSON_H


/** Types **/

/* General CDI configuration. */
struct cdi_config {
   char **spec_dirs;      // directories to search for CDI spec files
   bool devs_all_p;        // inject all devices found
   char **devids;          // user-requested devices
};


/** Function prototypes **/

void cdi_envs_get(const char *devid);
void cdi_init(struct cdi_config *cf);
