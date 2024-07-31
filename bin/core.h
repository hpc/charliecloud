/* Copyright © Triad National Security, LLC, and others.

   This interface contains Charliecloud’s core containerization features. */

#define _GNU_SOURCE
#pragma once

#include <stdbool.h>
#include <sys/types.h>


/** Types **/

enum bind_dep {
   BD_REQUIRED,  // both source and destination must exist
   BD_OPTIONAL,  // if either source or destination missing, do nothing
   BD_MAKE_DST,  // source must exist, try to create destination if it doesn't
};

struct bind {
   char *src;
   char *dst;
   enum bind_dep dep;
};

struct container;  // forward declaration to avoid definition loop
typedef void (hookf_t)(struct container *, void *);
struct hook {
   char *name;
   hookf_t *f;
   void *data;
};

enum hook_dup {    // see hook_add()
   HOOK_DUP_OK,
   HOOK_DUP_SKIP,
   HOOK_DUP_FAIL
};

enum img_type {
   IMG_DIRECTORY,  // normal directory, perhaps an external mount of some kind
   IMG_SQUASH,     // SquashFS archive file (not yet mounted)
   IMG_NAME,       // name of image in storage
   IMG_NONE,       // image type is not set yet
};

struct container {
   struct bind *binds;
   gid_t container_gid;  // GID to use in container
   uid_t container_uid;  // UID to use in container
   bool env_expand;      // expand variables in --set-env
   struct hook *hooks_prestart;  // prestart hook functions and their arguments
   char *host_home;      // if --home, host path to user homedir, else NULL
   char *img_ref;        // image description from command line
   char **ldconfigs;     // directories to pass to image’s ldconfig(8)
   char *newroot;        // path to new root directory
   bool join;            // is this a synchronized join?
   int join_ct;          // number of peers in a synchronized join
   pid_t join_pid;       // process in existing namespace to join
   char *join_tag;       // identifier for synchronized join
   char *overlay_size;   // size of overlaid tmpfs (NULL for no overlay)
   bool private_passwd;  // don’t bind custom /etc/{passwd,group}
   bool private_tmp;     // don’t bind host's /tmp
   enum img_type type;   // directory, SquashFS, etc.
   bool writable;        // re-mount image read-write
};


/** Function prototypes **/

void containerize(struct container *c);
void hook_add(struct hook **hook_list, enum hook_dup dup,
              const char *name, hookf_t *f, void *d);
void hooks_run(struct container *c, struct hook **hook_list);
enum img_type image_type(const char *ref, const char *images_dir);
char *img_name2path(const char *name, const char *storage_dir);
void run_user_command(char *argv[], const char *initial_dir);
