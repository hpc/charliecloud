/* Copyright © Triad National Security, LLC, and others.

   This interface contains all functions that deal with JSON: OCI, CDI, and
   friends. */

#define _GNU_SOURCE
#pragma once

#include "config.h"
#include "ch_core.h"

#include CJSON_H


/** Function prototypes **/

void cdi_update(struct container *c, char ** devids);
