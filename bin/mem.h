/* Memory management routines. */

#define _GNU_SOURCE
#pragma once

#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

/** Function prototypes **/

char *ch_asprintf(const char *fmt, ...);
pid_t ch_fork(void);
void ch_free_noop(void *p);
char *ch_getdelim(FILE *fp, char delim);
void ch_memory_exit(void);
void ch_memory_init(void);
void ch_memory_log(const char *when);
void *ch_malloc(size_t size, bool pointerful);
void *ch_malloc_pointerful(size_t size);
void *ch_malloc_zeroed(size_t size, bool pointerful);
void *ch_realloc(void *p, size_t size, bool pointerful);
char *ch_strdup(const char *src);
char *ch_vasprintf(const char *fmt, va_list ap);
void garbageinate(const char *when);
