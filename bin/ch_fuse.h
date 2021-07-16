/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <stdbool.h>

/** Types **/

/** Function prototypes **/

bool imgdir_p(const char *path);
void sq_clean();
char *sq_mount(char *mountdir, char *filepath);
