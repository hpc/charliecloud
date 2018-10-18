/* Copyright © Los Alamos National Security, LLC, and others. */

/* Note: This program does not bother to free memory allocations, since they
   are modest and the program is short-lived. */

#define _GNU_SOURCE
#include <argp.h>
#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "charliecloud.h"


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
You cannot use this program to actually change your UID.";

const char args_doc[] = "NEWROOT CMD [ARG...]";

const struct argp_option options[] = {
   { "bind",        'b', "SRC[:DST]", 0,
     "mount SRC at guest DST (default /mnt/0, /mnt/1, etc.)"},
   { "cd",          'c', "DIR", 0, "initial working directory in container"},
   { "gid",         'g', "GID", 0, "run as GID within container" },
   { "join",        'j', 0,     0, "use same container as peer ch-run" },
   { "join-pid",     -5, "PID", 0, "join a namespace using a PID" },
   { "join-ct",      -3, "N",   0, "number of ch-run peers (implies --join)" },
   { "join-tag",     -4, "TAG", 0, "label for peer group (implies --join)" },
   { "no-home",      -2, 0,     0, "do not bind-mount your home directory"},
   { "private-tmp", 't', 0,     0, "use container-private /tmp" },
   { "uid",         'u', "UID", 0, "run as UID within container" },
   { "verbose",     'v', 0,     0, "be more verbose (debug if repeated)" },
   { "version",     'V', 0,     0, "print version and exit" },
   { "write",       'w', 0,     0, "mount image read-write"},
   { 0 }
};

struct args {
   struct container c;
   char *initial_dir;
};

/** Function prototypes **/

void fix_environment(struct args *args);
bool get_first_env(char **array, char **name, char **value);
int join_ct(int cli_ct);
char *join_tag(char *cli_tag);
int parse_int(char *s, bool extra_ok, char *error_tag);
static error_t parse_opt(int key, char *arg, struct argp_state *state);
void privs_verify_invoking();


/** Global variables **/

const struct argp argp = { options, parse_opt, args_doc, usage };


/** Main **/

int main(int argc, char *argv[])
{
   struct args args;
   int arg_next;
   int c_argc;
   char ** c_argv;

   privs_verify_invoking();

   T_ (args.c.binds = calloc(1, sizeof(struct bind)));
   args.c.container_gid = getegid();
   args.c.container_uid = geteuid();
   args.initial_dir = NULL;
   args.c.join = false;
   args.c.join_pid = 0;
   args.c.join_ct = 0;
   args.c.join_tag = NULL;
   args.c.private_home = false;
   args.c.private_tmp = false;
   verbose = 1;  // in charliecloud.h

   Z_ (setenv("ARGP_HELP_FMT", "opt-doc-col=25,no-dup-args-note", 0));
   Z_ (argp_parse(&argp, argc, argv, 0, &(arg_next), &args));

   Te (arg_next < argc - 1, "NEWROOT and/or CMD not specified");
   args.c.newroot = realpath(argv[arg_next], NULL);
   Tf (args.c.newroot != NULL, "can't find image: %s", argv[arg_next]);
   arg_next++;

   if (args.c.join) {
      args.c.join_ct = join_ct(args.c.join_ct);
      args.c.join_tag = join_tag(args.c.join_tag);
   }

   c_argc = argc - arg_next;
   T_ (c_argv = calloc(c_argc + 1, sizeof(char *)));
   for (int i = 0; i < c_argc; i++)
      c_argv[i] = argv[i + arg_next];

   INFO("verbosity: %d", verbose);
   INFO("newroot: %s", args.c.newroot);
   INFO("container uid: %u", args.c.container_uid);
   INFO("container gid: %u", args.c.container_gid);
   INFO("join: %d %d %s %d", args.c.join, args.c.join_ct, args.c.join_tag, args.c.join_pid);
   INFO("private /tmp: %d", args.c.private_tmp);

   containerize(&args.c);
   fix_environment(&args);
   run_user_command(c_argv, args.initial_dir); // should never return
   exit(EXIT_FAILURE);
}


/** Supporting functions **/

/* Adjust environment variables. */
void fix_environment(struct args *args)
{
   char *old, *new;

   // $HOME: Set to /home/$USER unless --no-home specified.
   old = getenv("HOME");
   if (!args->c.private_home) {
      old = getenv("USER");
      if (old == NULL) {
         WARNING("$USER not set; cannot rewrite $HOME");
      } else {
         T_ (1 <= asprintf(&new, "/home/%s", old));
         Z_ (setenv("HOME", new, 1));
      }
   }

   // $PATH: Append /bin if not already present.
   old = getenv("PATH");
   if (old == NULL) {
      WARNING("$PATH not set");
   } else if (strstr(old, "/bin") != old && !strstr(old, ":/bin")) {
      T_ (1 <= asprintf(&new, "%s:/bin", old));
      Z_ (setenv("PATH", new, 1));
      INFO("new $PATH: %s", new);
   }
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

/* Find an appropriate join count; assumes --join was specified or implied.
   Exit with error if no valid value is available. */
int join_ct(int cli_ct)
{
   int j = 0;
   char *ev_name, *ev_value;

   if (cli_ct != 0) {
      INFO("join: peer group size from command line");
      j = cli_ct;
      goto end;
   }

   if (get_first_env(JOIN_CT_ENV, &ev_name, &ev_value)) {
      INFO("join: peer group size from %s", ev_name);
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
      INFO("join: peer group tag from command line");
      tag = cli_tag;
      goto end;
   }

   if (get_first_env(JOIN_TAG_ENV, &ev_name, &ev_value)) {
      INFO("join: peer group tag from %s", ev_name);
      tag = ev_value;
      goto end;
   }

   INFO("join: peer group tag from getppid(2)");
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
   Tf (errno == 0, error_tag);
   Ze (end == s, "%s: no digits found", error_tag);
   if (!extra_ok)
      Te (*end == 0, "%s: extra characters after digits", error_tag);
   Te (l >= INT_MIN && l <= INT_MAX, "%s: out of range", error_tag);
   return (int)l;
}

/* Parse one command line option. Called by argp_parse(). */
static error_t parse_opt(int key, char *arg, struct argp_state *state)
{
   struct args *args = state->input;
   int i;

   switch (key) {
   case -2: // --private-home
      args->c.private_home = true;
      break;
   case -3: // --join-ct
      args->c.join = true;
      args->c.join_ct = parse_int(arg, false, "--join-ct");
      break;
   case -4: // --join-tag
      args->c.join = true;
      args->c.join_tag = arg;
      break;
   case -5: // --join-pid
      args->c.join = true;
      args->c.join_pid = parse_int(arg, false, "--join-pid");
      break;
   case 'c':
      args->initial_dir = arg;
      break;
   case 'b':
      for (i = 0; args->c.binds[i].src != NULL; i++) // count existing binds
         ;
      T_ (args->c.binds = realloc(args->c.binds, (i+2) * sizeof(struct bind)));
      args->c.binds[i+1].src = NULL;                 // terminating zero
      args->c.binds[i].src = strsep(&arg, ":");
      assert(args->c.binds[i].src != NULL);
      if (arg)
         args->c.binds[i].dst = arg;
      else // arg is NULL => no destination specified
         T_ (1 <= asprintf(&(args->c.binds[i].dst), "/mnt/%d", i));
      Te (args->c.binds[i].src[0] != 0, "--bind: no source provided");
      Te (args->c.binds[i].dst[0] != 0, "--bind: no destination provided");
      break;
   case 'g':
      i = parse_int(arg, false, "--gid");
      Te (i >= 0, "--gid: must be non-negative");
      args->c.container_gid = (gid_t) i;
      break;
   case 'j':
      args->c.join = true;
      break;
   case 't':
      args->c.private_tmp = true;
      break;
   case 'u':
      i = parse_int(arg, false, "--uid");
      Te (i >= 0, "--uid: must be non-negative");
      args->c.container_uid = (uid_t) i;
      break;
   case 'V':
      version();
      exit(EXIT_SUCCESS);
      break;
   case 'v':
      verbose++;
      Te(verbose <= 3, "--verbose can be specified at most twice");
      break;
   case 'w':
      args->c.writable = true;
      break;
   default:
      return ARGP_ERR_UNKNOWN;
   };

   return 0;
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
