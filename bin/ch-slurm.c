#define _GNU_SOURCE

#include <errno.h>
#include <linux/limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <unistd.h>

#include <slurm/spank.h>

#include "charliecloud.h"

SPANK_PLUGIN(ch-slurm, 1)
extern int errno;

static char *imagename = NULL;

void fix_environment(spank_t sp, struct container *c)
{
   char *name, *new_value;
   char old_value[PATH_MAX];

   // $HOME: Set to /home/$USER unless --no-home specified.
   if (!c->private_home) {
      spank_getenv(sp, "USER", old_value, PATH_MAX);
      // FIXME: the next line should test the return of the previous one
      if (old_value == NULL) {
         WARNING("$USER not set; cannot rewrite $HOME");
      } else {
         T_ (1 <= asprintf(&new_value, "/home/%s", old_value));
         //Z_ (setenv("HOME", new_value, 1));
         // FIXME: remove above line
         spank_setenv(sp, "HOME", new_value, true);
      }
   }

   // $PATH: Append /bin if not already present.
   spank_getenv(sp, "PATH", old_value, PATH_MAX);
   // FIXME: the next line should test the return of the previous one
   if (old_value == NULL) {
      WARNING("$PATH not set");
   } else if (   strstr(old_value, "/bin") != old_value
              && !strstr(old_value, ":/bin")) {
      T_ (1 <= asprintf(&new_value, "%s:/bin", old_value));
      //Z_ (setenv("PATH", new_value, 1));
      // FIXME: remove above line
      spank_setenv(sp, "PATH", new_value, true);
      INFO("new $PATH: %s", new_value);
   }
}


static int _opt_ch_image(int val, const char *optarg, int remote){
  char *givenimagename;

  slurm_info("opt_ch_image being initialized");
  slurm_info("Remote: %d", remote);
  slurm_info("Context: %d", spank_context());

  if(imagename == NULL){
    givenimagename = strdup(optarg);  // FIXME: check for failure
    imagename = basename(givenimagename);  // FIXME: check for corner cases: "", "/", "foo/", "/foo/", ...
  }

  if(strncmp(imagename, "", 1) == 0){
    slurm_error("Image name cannot be empty");
    return -1;
  }

  return 0;
}


int slurm_spank_init(spank_t sp, int ac, char **av){
  struct spank_option opt_ch_image = {
    .name = "ch-image",
    .arginfo = "image",
    .usage = "Charliecloud container image to run job in",
    .has_arg = 1,
    .val = 0,
    .cb = (spank_opt_cb_f) _opt_ch_image, // FIXME: need to add sanity checking
  };

  slurm_info("Plugin initializing");

  if (spank_context() != S_CTX_ALLOCATOR)
    spank_option_register(sp, &opt_ch_image);

  slurm_info("Number of options: %d", ac);

  return 0;
}


int slurm_spank_task_init(spank_t sp, int ac, char **av){
  uid_t euid;
  gid_t egid;
  struct container c;
  char old_home[PATH_MAX];

  slurm_info("in slurm_spank_task_init");
  if(imagename != NULL){
    slurm_info("Number of options: %d", ac);
    slurm_info("Image name: %s", imagename);

    euid = geteuid();
    egid = getegid();
    slurm_info("euid: %d", euid);

    prctl(PR_SET_DUMPABLE, 1, 0, 0, 0);

    c.binds = calloc(1, sizeof(struct bind));
    c.container_gid = egid;
    c.container_uid = euid;
    c.join = false;
    c.join_ct = 0;
    c.join_pid = 0;
    c.join_tag = NULL;
    c.private_home = false;
    c.private_tmp = false;
    spank_getenv(sp, "HOME", old_home, PATH_MAX);
    c.old_home = old_home;
    c.writable = false;

    slurm_info("Old home: %s", c.old_home);

    //c.newroot = "/images/mpihello";

    asprintf(&c.newroot, "/images/%s", imagename);  // FIXME: check for failure

    fix_environment(sp, &c);
    containerize(&c);
  }
}
