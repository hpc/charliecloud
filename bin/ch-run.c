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
#include "ch_core.h"
#include "ch_misc.h"


/** Constants and macros **/

/* Environment variables used by --join parameters. */
char *JOIN_CT_ENV[] =  { "OMPI_COMM_WORLD_LOCAL_SIZE",
                         "SLURM_STEP_TASKS_PER_NODE",
                         "SLURM_CPUS_ON_NODE",
                         NULL };
char *JOIN_TAG_ENV[] = { "SLURM_STEP_ID",
                         NULL };


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
   { "bind",          'b', "SRC[:DST]", 0,
     "mount SRC at guest DST (default: same as SRC)"},
   { "cd",            'c', "DIR",  0, "initial working directory in container"},
   { "env-no-expand", -10, 0,      0, "don't expand $ in --set-env input"},
   { "feature",       -11, "FEAT", 0, "exit successfully if FEAT is enabled" },
   { "gid",           'g', "GID",  0, "run as GID within container" },
   { "home",          -12, 0,      0, "mount host $HOME at guest /home/$USER" },
   { "join",          'j', 0,      0, "use same container as peer ch-run" },
   { "join-pid",       -5, "PID",  0, "join a namespace using a PID" },
   { "join-ct",        -3, "N",    0, "number of join peers (implies --join)" },
   { "join-tag",       -4, "TAG",  0, "label for peer group (implies --join)" },
   { "logging",        -17, "FAIL", OPTION_ARG_OPTIONAL, "fooooooo" },
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
   { "write",         'w', 0,      0, "mount image read-write"},
   { 0 }
};


/** Types **/

struct args {
   struct container c;
   struct env_delta *env_deltas;
   char *initial_dir;
#ifdef HAVE_SECCOMP
   bool seccomp_p;
#endif
   char *storage_dir;
   bool unsafe;
};


/** Function prototypes **/

void fix_environment(struct args *args);
bool get_first_env(char **array, char **name, char **value);
void img_directory_verify(const char *img_path, const struct args *args);
int join_ct(int cli_ct);
char *join_tag(char *cli_tag);
int parse_int(char *s, bool extra_ok, char *error_tag);
static error_t parse_opt(int key, char *arg, struct argp_state *state);
void parse_set_env(struct args *args, char *arg, int delim);
void privs_verify_invoking();
char *storage_default(void);
extern void warnings_reprint(void);


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

   Z_ (atexit(warnings_reprint));

#ifdef ENABLE_SYSLOG
   syslog(LOG_USER|LOG_INFO, "uid=%u args=%d: %s", getuid(), argc,
          argv_to_string(argv));
#endif

   username = getenv("USER");
   Te (username != NULL, "$USER not set");

   verbose = LL_INFO;  // in ch_misc.c
   args = (struct args){
      .c = (struct container){ .binds = list_new(sizeof(struct bind), 0),
                               .container_gid = getegid(),
                               .container_uid = geteuid(),
                               .env_expand = true,
                               .host_home = NULL,
                               .img_ref = NULL,
                               .newroot = NULL,
                               .join = false,
                               .join_ct = 0,
                               .join_pid = 0,
                               .join_tag = NULL,
                               .private_passwd = false,
                               .private_tmp = false,
                               .type = IMG_NONE,
                               .writable = false },
      .env_deltas = list_new(sizeof(struct env_delta), 0),
      .initial_dir = NULL,
#ifdef HAVE_SECCOMP
      .seccomp_p = false,
#endif
      .storage_dir = storage_default(),
      .unsafe = false };

   /* I couldn't find a way to set argp help defaults other than this
      environment variable. Kludge sets/unsets only if not already set. */
   if (getenv("ARGP_HELP_FMT"))
      argp_help_fmt_set = true;
   else {
      argp_help_fmt_set = false;
      Z_ (setenv("ARGP_HELP_FMT", "opt-doc-col=25,no-dup-args-note", 0));
   }
   Z_ (argp_parse(&argp, argc, argv, 0, &arg_next, &args));
   if (!argp_help_fmt_set)
      Z_ (unsetenv("ARGP_HELP_FMT"));

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

   if (getenv("TMPDIR") != NULL)
      host_tmp = getenv("TMPDIR");
   else
      host_tmp = "/tmp";

   c_argv = list_new(sizeof(char *), argc - arg_next);
   for (int i = 0; i < argc - arg_next; i++)
      c_argv[i] = argv[i + arg_next];

   VERBOSE("verbosity: %d", verbose);
   VERBOSE("image: %s", args.c.img_ref);
   VERBOSE("storage: %s", args.storage_dir);
   VERBOSE("newroot: %s", args.c.newroot);
   VERBOSE("container uid: %u", args.c.container_uid);
   VERBOSE("container gid: %u", args.c.container_gid);
   VERBOSE("join: %d %d %s %d", args.c.join, args.c.join_ct, args.c.join_tag,
           args.c.join_pid);
   VERBOSE("private /tmp: %d", args.c.private_tmp);
#ifdef HAVE_SECCOMP
   VERBOSE("seccomp: %d", args.seccomp_p);
#endif
   VERBOSE("unsafe: %d", args.unsafe);

   containerize(&args.c);
   fix_environment(&args);
#ifdef HAVE_SECCOMP
   if (args.seccomp_p)
      seccomp_install();
#endif
   run_user_command(c_argv, args.initial_dir); // should never return
   exit(EXIT_FAILURE);
}


/** Supporting functions **/

/* Adjust environment variables. Call once containerized, i.e., already
   pivoted into new root. */
void fix_environment(struct args *args)
{
   char *old_value, *new_value;

   // $HOME: If --home, set to “/home/$USER”.
   if (args->c.host_home) {
      Z_ (setenv("HOME", cat("/home/", username), 1));
   } else if (path_exists("/root", NULL, true)) {
      Z_ (setenv("HOME", "/root", 1));
   } else
      Z_ (setenv("HOME", "/", 1));

   // $PATH: Append /bin if not already present.
   old_value = getenv("PATH");
   if (old_value == NULL) {
      WARNING("$PATH not set");
   } else if (   strstr(old_value, "/bin") != old_value
              && !strstr(old_value, ":/bin")) {
      T_ (1 <= asprintf(&new_value, "%s:/bin", old_value));
      Z_ (setenv("PATH", new_value, 1));
      VERBOSE("new $PATH: %s", new_value);
   }

   // $TMPDIR: Unset.
   Z_ (unsetenv("TMPDIR"));

   // --set-env and --unset-env.
   for (size_t i = 0; args->env_deltas[i].action != ENV_END; i++) {
      struct env_delta ed = args->env_deltas[i];
      switch (ed.action) {
      case ENV_END:
         Te (false, "unreachable code reached");
         break;
      case ENV_SET_DEFAULT:
         ed.arg.vars = env_file_read("/ch/environment", ed.arg.delim);
         // fall through
      case ENV_SET_VARS:
         for (size_t j = 0; ed.arg.vars[j].name != NULL; j++)
            env_set(ed.arg.vars[j].name, ed.arg.vars[j].value,
                    args->c.env_expand);
         break;
      case ENV_UNSET_GLOB:
         env_unset(ed.arg.glob);
         break;
      }
   }

   // $CH_RUNNING is not affected by --unset-env or --set-env.
   Z_ (setenv("CH_RUNNING", "Weird Al Yankovic", 1));
}

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
      parse_set_env(args, arg, '\n');
      break;
   case -7: { // --unset-env
        struct env_delta ed;
        Te (strlen(arg) > 0, "--unset-env: GLOB must have non-zero length");
        ed.action = ENV_UNSET_GLOB;
        ed.arg.glob = arg;
        list_append((void **)&(args->env_deltas), &ed, sizeof(ed));
      } break;
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
      }
      else
         FATAL("unknown feature: %s", arg);
      break;
   case -12: // --home
      Tf (args->c.host_home = getenv("HOME"), "--home failed: $HOME not set");
      break;
   case -13: // --unsafe
      args->unsafe = true;
      break;
#ifdef HAVE_SECCOMP
   case -14: // --seccomp
      args->seccomp_p = true;
      break;
#endif
   case -16: // --warnings
      for (int i = 1; i <= parse_int(arg, false, "--warnings"); i++)
         WARNING("this is warning %d!", i);
      exit(0);
      break;
   case -17: // --logging
         if (arg == NULL) {
            logging_print(false);
         } else {
            logging_print((!strcmp(arg, "fail")));
         }
      break;
   case -15: // --set-env0
      parse_set_env(args, arg, '\0');
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
   case ARGP_KEY_NO_ARGS:
      argp_state_help(state, stderr, (  ARGP_HELP_SHORT_USAGE
                                      | ARGP_HELP_PRE_DOC
                                      | ARGP_HELP_LONG
                                      | ARGP_HELP_POST_DOC));
      exit(EXIT_FAILURE);
   default:
      return ARGP_ERR_UNKNOWN;
   };

   return 0;
}

void parse_set_env(struct args *args, char *arg, int delim)
{
   struct env_delta ed;

   if (arg == NULL) {
      ed.action = ENV_SET_DEFAULT;
      ed.arg.delim = delim;
   } else {
      ed.action = ENV_SET_VARS;
      if (strchr(arg, '=') == NULL)
         ed.arg.vars = env_file_read(arg, delim);
      else {
         ed.arg.vars = list_new(sizeof(struct env_var), 1);
         ed.arg.vars[0] = env_var_parse(arg, NULL, 0);
      }
   }
   list_append((void **)&(args->env_deltas), &ed, sizeof(ed));
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
