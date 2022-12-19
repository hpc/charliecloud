/* Copyright © Triad National Security, LLC, and others.

   This interface contains Charliecloud's core containerization features. */

#define _GNU_SOURCE
#include <stdbool.h>


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

enum img_type {
   IMG_DIRECTORY,  // normal directory, perhaps an external mount of some kind
   IMG_SQUASH,     // SquashFS archive file (not yet mounted)
   IMG_NAME,       // name of image in storage
   IMG_NONE,       // image type is not set yet
};

struct container {
   struct bind *binds;
   bool ch_ssh;          // bind /usr/bin/ch-ssh?
   gid_t container_gid;  // GID to use in container
   uid_t container_uid;  // UID to use in container
   bool env_expand;      // expand variables in --set-env
   char *host_home;      // if --home, host path to user homedir, else NULL
   char *img_path;       // path to image
   char *img_ref;        // image reference (by name)
   char *newroot;        // path to new root directory
   bool join;            // is this a synchronized join?
   int join_ct;          // number of peers in a synchronized join
   pid_t join_pid;       // process in existing namespace to join
   char *join_tag;       // identifier for synchronized join
   bool private_passwd;  // don't bind custom /etc/{passwd,group}
   bool private_tmp;     // don't bind host's /tmp
   enum img_type type;   // directory, SquashFS, etc.
   bool writable;        // re-mount image read-write
};


/** Function prototypes **/

void containerize(struct container *c);
enum img_type img_type_get(const char *path, char *storage);
void run_user_command(char *argv[], const char *initial_dir);
