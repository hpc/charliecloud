/* Copyright © Triad National Security, LLC, and others.

   This interface contains Charliecloud's core containerization features. */

#define _GNU_SOURCE
#include <stdbool.h>


/** Types **/

struct bind {
   char *src;
   char *dst;
};

enum bind_dep {
   BD_REQUIRED,  // both source and destination must exist
   BD_OPTIONAL   // if either source or destination missing, do nothing
};

struct container {
   struct bind *binds;
   bool ch_ssh;         // bind /usr/bin/ch-ssh?
   gid_t container_gid;
   uid_t container_uid;
   char *newroot;
   bool join;           // is this a synchronized join?
   int join_ct;         // number of peers in a synchronized join
   pid_t join_pid;      // process in existing namespace to join
   char *join_tag;      // identifier for synchronized join
   bool private_home;   // don't bind user home directory
   bool private_passwd; // don't bind custom /etc/{passwd,group}
   bool private_tmp;    // don't bind host's /tmp
   char *old_home;      // host path to user's home directory (i.e. $HOME)
   bool writable;
};


/** Function prototypes **/

void containerize(struct container *c);
void run_user_command(char *argv[], char *initial_dir);
