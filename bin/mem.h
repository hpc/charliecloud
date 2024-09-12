/* Memory management routines. */

#define _GNU_SOURCE
#pragma once

#include <stdbool.h>
#include <stdio.h>

/** Function prototypes **/

char *ch_asprintf(const char *fmt, ...);
char *ch_getdelim(FILE *fp, char delim);
void ch_memory_init();
void ch_memory_log(const char *when);
void *ch_malloc(size_t size, bool pointerful);
void *ch_realloc(void *p, size_t size, bool pointerful);
char *ch_strdup(const char *src);
void garbageinate(void);
