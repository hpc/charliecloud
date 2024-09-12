/* Copyright © Triad National Security, LLC, and others. */

/* Note: This program does not bother to free memory allocations, since they
   are modest and the program is short-lived. */

#define _GNU_SOURCE
#include <argp.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <sys/mman.h>
#include <unistd.h>

#include "config.h"
#include "core.h"
#include "hook.h"
#ifdef HAVE_JSON
#include "json.h"
#endif
#include "mem.h"
#include "misc.h"
#ifdef HAVE_SECCOMP
#include "seccomp.h"
#endif


/** Types **/

enum env_option_type {
   ENV_END = 0,  // list terminator sentinel
   ENV_SET,      // --set-env
   ENV_SET0,     // --set-env0
   ENV_UNSET,    // --unset-env
   ENV_CDI_DEV,  // --device (specific device)
   ENV_CDI_ALL,  // --devices (all known devices)
};

struct env_option {
   enum env_option_type opt;
   char *arg;
};

struct args {
   struct container c;
#ifdef HAVE_JSON
   struct cdi_config cdi;
#endif
   struct env_option *env_options;
   enum log_color_when log_color;
   enum log_test log_test;
   char *initial_dir;
#ifdef HAVE_SECCOMP
   bool seccomp_p;
#endif
   char *storage_dir;
   bool unsafe;
};

struct log_color_synonym {
   char *name;
   enum log_color_when color;
};


/** Constants and macros **/

/* Environment variables used by --join parameters. */
char *JOIN_CT_ENV[] =  { "OMPI_COMM_WORLD_LOCAL_SIZE",
                         "SLURM_STEP_TASKS_PER_NODE",
                         "SLURM_CPUS_ON_NODE",
                         NULL };
char *JOIN_TAG_ENV[] = { "SLURM_STEP_ID",
                         NULL };

/* Default overlaid tmpfs size. */
char *WRITE_FAKE_DEFAULT = "12%";

/* Log color WHEN synonyms. Note that no argument (i.e., bare --color) is
   handled separately. */
struct log_color_synonym log_color_synonyms[] = {
   { "auto",    LL_COLOR_AUTO },
   { "tty",     LL_COLOR_AUTO },
   { "if-tty",  LL_COLOR_AUTO },
   { "yes",     LL_COLOR_YES },
   { "always",  LL_COLOR_YES },
   { "force",   LL_COLOR_YES },
   { "no",      LL_COLOR_NO },
   { "never",   LL_COLOR_NO },
   { "none",    LL_COLOR_NO },
   { NULL,      LL_COLOR_NULL } };


/** Command line options **/

const char usage[] = "\
\n\
Run a command in a Charliecloud container.\n\
\v\
Example:\n\
\n\
  $ ch-run /data/foo -- echo hello\n\
  hello\n\
\n\
You cannot use this program to actually change your UID.\n";

const char args_doc[] = "IMAGE -- COMMAND [ARG...]";

/* Note: Long option numbers, once issued, are permanent; i.e., if you remove
   one, don’t re-number the others. */
const struct argp_option options[] = {
   { "abort-fatal",   -21, 0,      0,
     "exit abnormally on error, maybe dumping core" },
   { "bind",          'b', "SRC[:DST]", 0,
     "mount SRC at guest DST (default: same as SRC)"},
   { "cd",            'c', "DIR",  0, "initial working directory in container"},
#ifdef HAVE_JSON
   { "cdi-dirs",      -19, "DIRS", 0, "director(y|ies) containing CDI specs" },
#endif
   { "color",         -20, "WHEN", OPTION_ARG_OPTIONAL,
                           "specify when to use colored logging" },
#ifdef HAVE_JSON
   { "device",        -18, "DEV",  0, "inject CDI device(s) DEV (repeatable)" },
   { "devices",       'd', 0,      0, "inject default CDI devices" },
#endif
   { "env-no-expand", -10, 0,      0, "don't expand $ in --set-env input"},
   { "feature",       -11, "FEAT", 0, "exit successfully if FEAT is enabled" },
   { "gid",           'g', "GID",  0, "run as GID within container" },
   { "home",          -12, 0,      0, "mount host $HOME at guest /home/$USER" },
   { "join",          'j', 0,      0, "use same container as peer ch-run" },
   { "join-pid",       -5, "PID",  0, "join a namespace using a PID" },
   { "join-ct",        -3, "N",    0, "number of join peers (implies --join)" },
   { "join-tag",       -4, "TAG",  0, "label for peer group (implies --join)" },
   { "test",          -17, "TEST", 0, "do test TEST" },
   { "mount",         'm', "DIR",  0, "SquashFS mount point"},
   { "no-passwd",      -9, 0,      0, "don't bind-mount /etc/{passwd,group}"},
   { "private-tmp",   't', 0,      0, "use container-private /tmp" },
   { "quiet",         'q', 0,      0, "print less output (can be repeated)"},
#ifdef HAVE_SECCOMP
   { "seccomp",       -14, 0,      0,
                           "fake success for some syscalls with seccomp(2)"},
#endif
   { "set-env",        -6, "ARG",  OPTION_ARG_OPTIONAL,
                           "set env. variables per ARG (newline-delimited)"},
   { "set-env0",      -15, "ARG",  OPTION_ARG_OPTIONAL,
                           "set env. variables per ARG (null-delimited)"},
   { "storage",       's', "DIR",  0, "set DIR as storage directory"},
   { "uid",           'u', "UID",  0, "run as UID within container" },
   { "unsafe",        -13, 0,      0, "do unsafe things (internal use only)" },
   { "unset-env",      -7, "GLOB", 0, "unset environment variable(s)" },
   { "verbose",       'v', 0,      0, "be more verbose (can be repeated)" },
   { "version",       'V', 0,      0, "print version and exit" },
   { "warnings",      -16, "NUM",  0, "log NUM warnings and exit" },
   { "write",         'w', 0,      0, "mount image read-write (avoid)"},
   { "write-fake",    'W', "SIZE", OPTION_ARG_OPTIONAL,
                           "overlay read-write tmpfs on top of image" },
   { 0 }
};


/** Function prototypes **/

bool get_first_env(char **array, char **name, char **value);
void hooks_env_install(struct args *args);
void img_directory_verify(const char *img_path, const struct args *args);
int join_ct(int cli_ct);
char *join_tag(char *cli_tag);
void parse_env(struct env_option **opts, enum env_option_type opt, char *arg);
int parse_int(char *s, bool extra_ok, char *error_tag);
static error_t parse_opt(int key, char *arg, struct argp_state *state);
void privs_verify_invoking();
char *storage_default(void);
void write_fake_enable(struct args *args, char *overlay_size);


/** Global variables **/

const struct argp argp = { options, parse_opt, args_doc, usage };
extern char **environ;  // see environ(7)
extern char *warnings;


/** Main **/

int main(int argc, char *argv[])
{
   bool argp_help_fmt_set;
   struct args args;
   int arg_next;
   char ** c_argv;

   // initialize “warnings” buffer
   warnings = mmap(NULL, WARNINGS_SIZE, PROT_READ | PROT_WRITE,
                   MAP_SHARED | MAP_ANONYMOUS, -1, 0);
   T_ (warnings != MAP_FAILED);

   privs_verify_invoking();
   ch_memory_init();

   Z_ (atexit(warnings_reprint));

#ifdef ENABLE_SYSLOG
   syslog(SYSLOG_PRI, "uid=%u args=%d: %s", getuid(), argc,
          argv_to_string(argv));
#endif

   username = getenv("USER");
   Te (username != NULL, "$USER not set");

   verbose = LL_INFO;  // in ch_misc.c
   args = (struct args){
      .c = (struct container){
         .binds = list_new(sizeof(struct bind), 0),
         .container_gid = getegid(),
         .container_uid = geteuid(),
         .env_expand = true,
         .hooks_prestart = list_new(sizeof(struct hook), 0),
         .host_home = NULL,
         .img_ref = NULL,
         .ldconfigs = list_new(sizeof(char *), 0),
         .newroot = NULL,
         .join = false,
         .join_ct = 0,
         .join_pid = 0,
         .join_tag = NULL,
         .overlay_size = NULL,
         .private_passwd = false,
         .private_tmp = false,
         .type = IMG_NONE,
         .writable = false
      },
#ifdef HAVE_JSON
      .cdi = (struct cdi_config){
         .spec_dirs = list_new_strings(':', env_get("CH_RUN_CDI_DIRS",
                                                    "/etc/cdi:/var/run/cdi")),
         .devs_all_p = false,
         .devids = list_new(sizeof(char *), 0),
      },
#endif
      .env_options = list_new(sizeof(struct env_option), 0),
      .initial_dir = NULL,
      .log_color = LL_COLOR_AUTO,
      .log_test = LL_TEST_NONE,
      .storage_dir = storage_default(),
      .unsafe = false
   };

   /* I couldn't find a way to set argp help defaults other than this
      environment variable. Kludge sets/unsets only if not already set. */
   if (getenv("ARGP_HELP_FMT"))
      argp_help_fmt_set = true;
   else {
      argp_help_fmt_set = false;
      Z_ (setenv("ARGP_HELP_FMT", "opt-doc-col=27,no-dup-args-note", 0));
   }
   Z_ (argp_parse(&argp, argc, argv, 0, &arg_next, &args));
   if (!argp_help_fmt_set)
      Z_ (unsetenv("ARGP_HELP_FMT"));

   logging_init(args.log_color, args.log_test);
   ch_memory_log("start");

   if (arg_next >= argc - 1) {
      printf("usage: ch-run [OPTION...] IMAGE -- COMMAND [ARG...]\n");
      FATAL("IMAGE and/or COMMAND not specified");
   }
   args.c.img_ref = argv[arg_next++];
   args.c.newroot = realpath_(args.c.newroot, true);
   args.storage_dir = realpath_(args.storage_dir, true);
   args.c.type = image_type(args.c.img_ref, args.storage_dir);

   switch (args.c.type) {
   case IMG_DIRECTORY:
      if (args.c.newroot != NULL)  // --mount was set
         WARNING("--mount invalid with directory image, ignoring");
      args.c.newroot = realpath_(args.c.img_ref, false);
      img_directory_verify(args.c.newroot, &args);
      break;
   case IMG_NAME:
      args.c.newroot = img_name2path(args.c.img_ref, args.storage_dir);
      Tf (!args.c.writable || args.unsafe,
          "--write invalid when running by name");
      break;
   case IMG_SQUASH:
#ifndef HAVE_LIBSQUASHFUSE
      FATAL("this ch-run does not support internal SquashFS mounts");
#endif
      break;
   case IMG_NONE:
      FATAL("unknown image type: %s", args.c.img_ref);
      break;
   }

   if (args.c.join) {
      args.c.join_ct = join_ct(args.c.join_ct);
      args.c.join_tag = join_tag(args.c.join_tag);
   }

   c_argv = list_new(sizeof(char *), argc - arg_next);
   for (int i = 0; i < argc - arg_next; i++)
      c_argv[i] = argv[i + arg_next];

   host_tmp = env_get("TMPDIR", "/tmp");  // global in misc.c

   VERBOSE("verbosity: %d", verbose);
   VERBOSE("image: %s", args.c.img_ref);
   VERBOSE("storage: %s", args.storage_dir);
   VERBOSE("newroot: %s", args.c.newroot);
   VERBOSE("container uid: %u", args.c.container_uid);
   VERBOSE("container gid: %u", args.c.container_gid);
   VERBOSE("join: %d %d %s %d", args.c.join, args.c.join_ct, args.c.join_tag,
           args.c.join_pid);
   VERBOSE("host $TMPDIR: %s", host_tmp);
   VERBOSE("private /tmp: %d", args.c.private_tmp);
#ifdef HAVE_SECCOMP
   VERBOSE("seccomp: %s", bool_to_string(args.seccomp_p));
#endif
   VERBOSE("unsafe: %s", bool_to_string(args.unsafe));

#ifdef HAVE_JSON
   cdi_init(&args.cdi);
#endif
   hooks_env_install(&args);
   //cdi_hook_ldconfig_install(&args.c.hook_prestart, &args.cdi);

   containerize(&args.c);
   run_user_command(c_argv, args.initial_dir);  // should never return
   exit(EXIT_FAILURE);
}


/** Supporting functions **/

/* Find the first environment variable in array that is set; put its name in
   *name and its value in *value, and return true. If none are set, return
   false, and *name and *value are undefined. */
bool get_first_env(char **array, char **name, char **value)
{
   for (int i = 0; array[i] != NULL; i++) {
      *name = array[i];
      *value = getenv(*name);
      if (*value != NULL)
         return true;
   }

   return false;
}

/* Set the default environment variables that come before the user-specified
   environment changes. d must be NULL. */
void hook_envs_def_first(struct container *c, void *d)
{
   char *vnew, *vold;
   T_ (d == NULL);

   // $HOME: If --home, set to “/home/$USER”.
   if (c->host_home) {
      vnew = cat("/home/", username);
      env_set("HOME", vnew, false);
      free(vnew);
   } else if (path_exists("/root", NULL, true)) {
      env_set("HOME", "/root", false);
   } else
      env_set("HOME", "/", false);

   // $PATH: Append /bin if not already present.
   vold = getenv("PATH");
   if (vold == NULL) {
      WARNING("$PATH not set");
   } else if (strstr(vold, "/bin") != vold && !strstr(vold, ":/bin")) {
      T_ (1 <= asprintf(&vnew, "%s:/bin", vold));
      env_set("PATH", vnew, false);
   }

   // $TMPDIR: Unset.
   Z_ (unsetenv("TMPDIR"));
}

/* Set the default environment variables that come after the user-specified
   changes. d must be NULL. */
void hook_envs_def_last(struct container *c, void *d)
{
   T_ (d == NULL);
   env_set("CH_RUNNING", "Weird Al Yankovic", false);
}

/* Install pre-start hooks for environment variable changes. */
void hooks_env_install(struct args *args)
{
   hook_add(&args->c.hooks_prestart, HOOK_DUP_FAIL,
            "env-def-first", hook_envs_def_first, NULL);

   for (int i = 0; args->env_options[i].opt != ENV_END; i++) {
      char *name;
      hookf_t *f;
      void *d;
      enum env_option_type opt = args->env_options[i].opt;
      char *arg = args->env_options[i].arg;

      switch (opt) {
      case ENV_SET:
      case ENV_SET0:
         int delim = ENV_SET ? '\n' : '\0';
         if (args == NULL) {                 // guest path; defer file read
            struct env_file *ef;
            name = "env-set-gfile";
            f = hook_envs_set_file;
            T_ (ef = malloc(sizeof(struct env_file)));
            ef->path = arg;
            ef->delim = delim;
            ef->expand = args->c.env_expand;
            d = ef;
         } else {
            f = hook_envs_set;
            if (strchr(arg, '=') == NULL) {  // host path; read file now
               name = "env-set-hfile";
               d = env_file_read(arg, delim);
            } else {                         // direct set
               name = "env-set-direct";
               d = list_new(sizeof(struct env_var), 1);
               ((struct env_var *)d)[0] = env_var_parse(arg, NULL, 0);
            }
         }
         break;
      case ENV_UNSET:
         name = "env-unset";
         f = hook_envs_unset;
         d = arg;
         break;
      case ENV_CDI_DEV:
         name = "env-set-cdi";
         f = hook_envs_set;
         //d = cdi_envs_get(arg);
         break;
      case ENV_CDI_ALL:
         name = "env-set-cdi-all";
         f = hook_envs_set;
         //d = cdi_envs_get(NULL);
      case ENV_END:
         T_ (false);  // unreachable
         break;
      }
      hook_add(&args->c.hooks_prestart, HOOK_DUP_OK, name, f, d);
   }

   hook_add(&args->c.hooks_prestart, HOOK_DUP_FAIL,
            "env-def-last", hook_envs_def_last, NULL);
}

/* Validate that it’s OK to run the IMG_DIRECTORY format image at path; if
   not, exit with error. */
void img_directory_verify(const char *newroot, const struct args *args)
{
   Te (args->c.newroot != NULL, "can't find image: %s", args->c.newroot);
   Te (args->unsafe || !path_subdir_p(args->storage_dir, args->c.newroot),
       "can't run directory images from storage (hint: run by name)");
}

/* Find an appropriate join count; assumes --join was specified or implied.
   Exit with error if no valid value is available. */
int join_ct(int cli_ct)
{
   int j = 0;
   char *ev_name, *ev_value;

   if (cli_ct != 0) {
      VERBOSE("join: peer group size from command line");
      j = cli_ct;
      goto end;
   }

   if (get_first_env(JOIN_CT_ENV, &ev_name, &ev_value)) {
      VERBOSE("join: peer group size from %s", ev_name);
      j = parse_int(ev_value, true, ev_name);
      goto end;
   }

end:
   Te(j > 0, "join: no valid peer group size found");
   return j;
}

/* Find an appropriate join tag; assumes --join was specified or implied. Exit
   with error if no valid value is found. */
char *join_tag(char *cli_tag)
{
   char *tag;
   char *ev_name, *ev_value;

   if (cli_tag != NULL) {
      VERBOSE("join: peer group tag from command line");
      tag = cli_tag;
      goto end;
   }

   if (get_first_env(JOIN_TAG_ENV, &ev_name, &ev_value)) {
      VERBOSE("join: peer group tag from %s", ev_name);
      tag = ev_value;
      goto end;
   }

   VERBOSE("join: peer group tag from getppid(2)");
   T_ (1 <= asprintf(&tag, "%d", getppid()));

end:
   Te(tag[0] != '\0', "join: peer group tag cannot be empty string");
   return tag;
}

/* Parse an integer string arg and return the result. If an error occurs,
   print a message prefixed by error_tag and exit. If not extra_ok, additional
   characters remaining after the integer are an error. */
int parse_int(char *s, bool extra_ok, char *error_tag)
{
   char *end;
   long l;

   errno = 0;
   l = strtol(s, &end, 10);
   Ze (end == s, "%s: no digits found", error_tag);
   Ze (errno == ERANGE || l < INT_MIN || l > INT_MAX,
       "%s: out of range", error_tag);
   Tf (errno == 0, error_tag);
   if (!extra_ok)
      Te (*end == 0, "%s: extra characters after digits", error_tag);
   return (int)l;
}

/* Parse one command line option. Called by argp_parse(). */
static error_t parse_opt(int key, char *arg, struct argp_state *state)
{
   struct args *args = state->input;
   int i;

   switch (key) {
   case -3: // --join-ct
      args->c.join = true;
      args->c.join_ct = parse_int(arg, false, "--join-ct");
      break;
   case -4: // --join-tag
      args->c.join = true;
      args->c.join_tag = arg;
      break;
   case -5: // --join-pid
      args->c.join_pid = parse_int(arg, false, "--join-pid");
      break;
   case -6: // --set-env
      parse_env(&args->env_options, ENV_SET, arg);
      break;
   case -7: // --unset-env
      parse_env(&args->env_options, ENV_UNSET, arg);
      break;
   case -9: // --no-passwd
      args->c.private_passwd = true;
      break;
   case -10: // --env-no-expand
      args->c.env_expand = false;
      break;
   case -11: // --feature
      if (!strcmp(arg, "extglob")) {
#ifdef HAVE_FNM_EXTMATCH
         exit(0);
#else
         exit(1);
#endif
      } else if (!strcmp(arg, "overlayfs")) {
#ifdef HAVE_OVERLAYFS
         exit(0);
#else
         exit(1);
#endif
      } else if (!strcmp(arg, "seccomp")) {
#ifdef HAVE_SECCOMP
         exit(0);
#else
         exit(1);
#endif
      } else if (!strcmp(arg, "squash")) {
#ifdef HAVE_LIBSQUASHFUSE
         exit(0);
#else
         exit(1);
#endif
      } else if (!strcmp(arg, "tmpfs-xattrs")) {
#ifdef HAVE_TMPFS_XATTRS
         exit(0);
#else
         exit(1);
#endif
      }
      else
         FATAL("unknown feature: %s", arg);
      break;
   case -12: // --home
      Tf (args->c.host_home = getenv("HOME"), "--home failed: $HOME not set");
      if (args->c.overlay_size == NULL) {
         VERBOSE("--home specified; also setting --write-fake");
         args->c.overlay_size = WRITE_FAKE_DEFAULT;
      }
      break;
   case -13: // --unsafe
      args->unsafe = true;
      break;
#ifdef HAVE_SECCOMP
   case -14: // --seccomp
      hook_add(&args->c.hooks_prestart, HOOK_DUP_SKIP,
               "seccomp", hook_seccomp_install, NULL);
      break;
#endif
   case -15: // --set-env0
      parse_env(&args->env_options, ENV_SET0, arg);
      break;
   case -16: // --warnings
      for (int i = 1; i <= parse_int(arg, false, "--warnings"); i++)
         WARNING("this is warning %d!", i);
      exit(0);
      break;
   case -17: // --test
      if (!strcmp(arg, "log"))
         args->log_test = LL_TEST_YES;
      else if (!strcmp(arg, "log-fail"))
         args->log_test = LL_TEST_FATAL;
      else
         FATAL("invalid --test argument: %s; see source code", arg);
      break;
#ifdef HAVE_JSON
   case -18: { // --device
         struct env_option ope;
         Te (strlen(arg) > 0, "--device: DEV must be non-empty");
         write_fake_enable(args, NULL);
         list_append((void **)&args->cdi.devids, &arg, sizeof(arg));
         ope.opt = ENV_CDI_DEV;
         ope.arg = arg;
         list_append((void **)&args->env_options, &ope, sizeof(ope));
      } break;
   case -19: // --cdi-dirs
      Te (strlen(arg) > 0, "--cdi-dirs: PATHS must be non-empty");
      list_free_shallow((void ***)&args->cdi.spec_dirs);
      args->cdi.spec_dirs = list_new_strings(':', arg);
      break;
#endif
   case -20: // --color
      if (arg == NULL)
         args->log_color = LL_COLOR_AUTO;
      args->log_color = LL_COLOR_NULL;
      for (int i = 0; true; i++) {
         if (log_color_synonyms[i].name == NULL)
            break;
         if (!strcmp(arg, log_color_synonyms[i].name)) {
            args->log_color = log_color_synonyms[i].color;
            break;
         }
      }
      Tf (args->log_color != LL_COLOR_NULL, "--color: invalid arg: %s", arg);
      break;
   case -21: // --abort-fatal
      abort_fatal = true;  // in misc.c
      break;
   case 'b': {  // --bind
         char *src, *dst;
         for (i = 0; args->c.binds[i].src != NULL; i++) // count existing binds
            ;
         T_ (args->c.binds = realloc(args->c.binds,
                                     (i+2) * sizeof(struct bind)));
         args->c.binds[i+1].src = NULL;                 // terminating zero
         args->c.binds[i].dep = BD_MAKE_DST;
         // source
         src = strsep(&arg, ":");
         T_ (src != NULL);
         Te (src[0] != 0, "--bind: no source provided");
         args->c.binds[i].src = src;
         // destination
         dst = arg ? arg : src;
         Te (dst[0] != 0, "--bind: no destination provided");
         Te (strcmp(dst, "/"), "--bind: destination can't be /");
         Te (dst[0] == '/', "--bind: destination must be absolute");
         args->c.binds[i].dst = dst;
      }
      break;
   case 'c':  // --cd
      args->initial_dir = arg;
      break;
#ifdef HAVE_JSON
   case 'd': {  // --devices
      // Can’t add the devices here b/c we don’t know the CDI spec dirs yet.
      struct env_option ope;
      args->cdi.devs_all_p = true;
      ope.opt = ENV_CDI_ALL;
      ope.arg = NULL;
      list_append((void **)&args->env_options, &ope, sizeof(ope));
      } break;
#endif
   case 'g':  // --gid
      i = parse_int(arg, false, "--gid");
      Te (i >= 0, "--gid: must be non-negative");
      args->c.container_gid = (gid_t) i;
      break;
   case 'j':  // --join
      args->c.join = true;
      break;
   case 'm':  // --mount
      Ze ((arg[0] == '\0'), "mount point can't be empty string");
      args->c.newroot = arg;
      break;
   case 's':  // --storage
      args->storage_dir = arg;
      if (!path_exists(arg, NULL, false))
         WARNING("storage directory not found: %s", arg);
      break;
   case 'q':  // --quiet
      Te(verbose <= 0, "--quiet incompatible with --verbose");
      verbose--;
      Te(verbose >= -3, "--quiet can be specified at most thrice");
      break;
   case 't':  // --private-tmp
      args->c.private_tmp = true;
      break;
   case 'u':  // --uid
      i = parse_int(arg, false, "--uid");
      Te (i >= 0, "--uid: must be non-negative");
      args->c.container_uid = (uid_t) i;
      break;
   case 'V':  // --version
      version();
      exit(EXIT_SUCCESS);
      break;
   case 'v':  // --verbose
      Te(verbose >= 0, "--verbose incompatible with --quiet");
      verbose++;
      Te(verbose <= 3, "--verbose can be specified at most thrice");
      break;
   case 'w':  // --write
      args->c.writable = true;
      break;
   case 'W':  // --write-fake
      write_fake_enable(args, arg);
      break;
   case ARGP_KEY_NO_ARGS:
      argp_state_help(state, stderr, (  ARGP_HELP_SHORT_USAGE
                                      | ARGP_HELP_PRE_DOC
                                      | ARGP_HELP_LONG
                                      | ARGP_HELP_POST_DOC));
      exit(EXIT_FAILURE);
   default:
      return ARGP_ERR_UNKNOWN;
   }

   return 0;
}

void parse_env(struct env_option **opts, enum env_option_type opt, char *arg)
{
   struct env_option eo = (struct env_option){ .opt = opt,
                                               .arg = arg };
   Te (arg == NULL || strlen(arg) > 0,
       "environment options: argument must have non-zero length");
   list_append((void **)opts, &eo, sizeof(eo));
}

/* Validate that the UIDs and GIDs are appropriate for program start, and
   abort if not.

   Note: If the binary is setuid, then the real UID will be the invoking user
   and the effective and saved UIDs will be the owner of the binary.
   Otherwise, all three IDs are that of the invoking user. */
void privs_verify_invoking()
{
   uid_t ruid, euid, suid;
   gid_t rgid, egid, sgid;

   Z_ (getresuid(&ruid, &euid, &suid));
   Z_ (getresgid(&rgid, &egid, &sgid));

   // Calling the program if user is really root is OK.
   if (   ruid == 0 && euid == 0 && suid == 0
       && rgid == 0 && egid == 0 && sgid == 0)
      return;

   // Now that we know user isn't root, no GID privilege is allowed.
   T_ (egid != 0);                           // no privilege
   T_ (egid == rgid && egid == sgid);        // no setuid or funny business

   // No UID privilege allowed either.
   T_ (euid != 0);                           // no privilege
   T_ (euid == ruid && euid == suid);        // no setuid or funny business
}

/* Return path to the storage directory, if -s is not specified. */
char *storage_default(void)
{
   char *storage = getenv("CH_IMAGE_STORAGE");

   if (storage == NULL)
      T_ (1 <= asprintf(&storage, "/var/tmp/%s.ch", username));

   return storage;
}

/* Enable the overlay if not already enabled. */
void write_fake_enable(struct args *args, char *overlay_size)
{
   if (overlay_size != NULL) {
      // new overlay size specified: use it regardless of previous enablement
      args->c.overlay_size = overlay_size;
   } else if (args->c.overlay_size == NULL) {
      // no new size, not yet enabled: enable with default size
      args->c.overlay_size = WRITE_FAKE_DEFAULT;
   } else {
      // no new size, already enabled: keep existing size, nothing to do
      T_ (args->c.overlay_size != NULL);
   }
}
