/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <stdbool.h>

/** Types **/
enum img {DIRECTORY, SQFS, OTHER};
/** Function prototypes **/

enum img img_type(const char *path);
void sq_clean();
void sq_mount(char *mountdir, char *filepath);
