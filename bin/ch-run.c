/* Copyright © Triad National Security, LLC, and others. */

/* Note: This program does not bother to free memory allocations, since they
   are modest and the program is short-lived. */

#define _GNU_SOURCE
#include <argp.h>
#include <fnmatch.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ch_core.h"
#include "ch_fuse.h"
#include "ch_misc.h"
#include "config.h"

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

const char args_doc[] = "NEWROOT CMD [ARG...]";

const struct argp_option options[] = {
   { "bind",          'b', "SRC[:DST]", 0,
     "mount SRC at guest DST (default: same as SRC)"},
   { "cd",            'c', "DIR",  0, "initial working directory in container"},
   { "ch-ssh",         -8, 0,      0, "bind ch-ssh into image"},
   { "env-no-expand", -10, 0,      0, "don't expand $ in --set-env input"},
   { "gid",           'g', "GID",  0, "run as GID within container" },
   { "join",          'j', 0,      0, "use same container as peer ch-run" },
   { "join-pid",       -5, "PID",  0, "join a namespace using a PID" },
   { "join-ct",        -3, "N",    0, "number of join peers (implies --join)" },
   { "join-tag",       -4, "TAG",  0, "label for peer group (implies --join)" },
   { "no-home",        -2, 0,      0, "don't bind-mount your home directory"},
   { "no-passwd",      -9, 0,      0, "don't bind-mount /etc/{passwd,group}"},
   { "private-tmp",   't', 0,      0, "use container-private /tmp" },
   { "set-env",        -6, "FILE", 0, "set environment variables in FILE"},
   { "squashmt",      's', "DIR",  0, "mount and run sqfs"},
   { "uid",           'u', "UID",  0, "run as UID within container" },
   { "unset-env",      -7, "GLOB", 0, "unset environment variable(s)" },
   { "verbose",       'v', 0,      0, "be more verbose (debug if repeated)" },
   { "version",       'V', 0,      0, "print version and exit" },
   { "write",         'w', 0,      0, "mount image read-write"},
   { 0 }
};

enum env_action { ENV_END = 0, ENV_SET, ENV_UNSET };

struct env_delta {
   enum env_action action;
   char *arg;
};

struct args {
   struct container c;
   struct env_delta *env_deltas;
   char *initial_dir;
};

/** Function prototypes **/

void env_delta_append(struct env_delta **ds, enum env_action act, char *arg);
void envs_set(char **lines, const int line_ct, const char *filename,
              const bool expand);
void fix_environment(struct args *args);
bool get_first_env(char **array, char **name, char **value);
int join_ct(int cli_ct);
char *join_tag(char *cli_tag);
int parse_int(char *s, bool extra_ok, char *error_tag);
static error_t parse_opt(int key, char *arg, struct argp_state *state);
void privs_verify_invoking();


/** Global variables **/

const struct argp argp = { options, parse_opt, args_doc, usage };
extern char **environ;  // see environ(7)

/** Main **/

int main(int argc, char *argv[])
{
   bool argp_help_fmt_set;
   struct args args;
   int arg_next;
   int c_argc;
   char ** c_argv;

   privs_verify_invoking();

   verbose = 1;  // in charliecloud.h
   args = (struct args){ .c = (struct container){ .ch_ssh = false,
                                                  .container_gid = getegid(),
                                                  .container_uid = geteuid(),
                                                  .env_expand = true,
                                                  .newroot = NULL,
                                                  .join = false,
                                                  .join_ct = 0,
                                                  .join_pid = 0,
                                                  .join_tag = NULL,
                                                  .private_home = false,
                                                  .private_passwd = false,
                                                  .private_tmp = false,
                                                  .old_home = getenv("HOME"),
                                                  .sq_mountpt = NULL,
                                                  .writable = false },
                         .initial_dir = NULL };
   // These need to be on the heap because we realloc(3) them later.
   T_ (args.c.binds = calloc(1, sizeof(struct bind)));
   T_ (args.env_deltas = calloc(1, sizeof(struct env_delta)));

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

   if(imgdir_p(argv[arg_next])) { //is img a sqfs?
      if(args.c.sq_mountpt == NULL)
         Te ((asprintf(&args.c.sq_mountpt, "/var/tmp/%s.ch/mnt", getenv("USER")) >= 0), "failed to create mount point");
      Ze (atexit(sq_clean), "exit handler set up failed");
      //overwrite user input to store directory mount location
      argv[arg_next] = sq_mount(args.c.sq_mountpt, argv[arg_next]);
   } else {
      if(args.c.sq_mountpt != NULL)
         WARNING("WARNING: invalid option -s, --squashmnt");
   }

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
   INFO("join: %d %d %s %d", args.c.join, args.c.join_ct, args.c.join_tag,
        args.c.join_pid);
   INFO("private /tmp: %d", args.c.private_tmp);

   fix_environment(&args);
   containerize(&args.c);
   run_user_command(c_argv, args.initial_dir); // should never return
   exit(EXIT_FAILURE);
}


/** Supporting functions **/

/* Append a new env_delta to an existing null-terminated list. */
void env_delta_append(struct env_delta **ds, enum env_action act, char *arg)
{
   int i;

   for (i = 0; (*ds)[i].action != ENV_END; i++) // count existing
         ;
   T_ (*ds = realloc(*ds, (i+2) * sizeof(struct env_delta)));
   (*ds)[i+1].action = ENV_END;
   (*ds)[i].action = act;
   (*ds)[i].arg = arg;
}

/* Set environment variables as specified in the array lines, which has length
   line_ct. filename is the source filename, or NULL if source was not a file;
   in that case, omit line number from any error messages. If expand, then
   expand variable notation as described in the man page. */
void envs_set(char **lines, const int line_ct, const char *filename,
              const bool expand)
{
   char *name, *value_old, *value_new, *lineno_str, *item;

   for (int i = 0; i < line_ct; i++) {
      bool first_written;

      // Skip blank lines.
      if (lines[i][0] == 0 || lines[i][0] == '\n')
         continue;

      // Split line into variable name and value.
      split(&name, &value_old, lines[i], '=');
      if (filename == NULL)
         lineno_str = "";
      else
         T_ (1 <= asprintf(&lineno_str, ":%d", i+1));
      Te (name != NULL, "--set-env: no delimiter: %s%s", filename, lineno_str);
      Te (name[0] != 0, "--set-env: empty name: %s%s", filename, lineno_str);

      // Strip leading and trailing single quotes from value, if both present.
      if (   strlen(value_old) >= 2
          && value_old[0] == '\''
          && value_old[strlen(value_old) - 1] == '\'') {
         value_old[strlen(value_old) - 1] = 0;
         value_old++;
      }

      // Walk through value fragments separated by colon and expand variables
      // per documentation.
      value_new = "";
      first_written = false;
      while (1) {                                  // loop executes ≥ once
         item = strsep(&value_old, ":");           // NULL -> no more items
         if (item == NULL)
            break;
         if (   expand                             // expansion requested
             && item[0] == '$' && item[1] != 0) {  // ≥1 char in variable name
            item = getenv(++item);                 // NULL if unset
            if (item != NULL && item[0] == 0)
               item = NULL;                        // convert empty to unset
         }
         if (item != NULL) {                       // NULL -> omit from output
            if (first_written)
               value_new = cat(value_new, ":");
            value_new = cat(value_new, item);
            first_written = true;
         }
      }

      // Save results.
      INFO("environment: %s=%s", name, value_new);
      Z_ (setenv(name, value_new, 1));
   }
}

/* Adjust environment variables. */
void fix_environment(struct args *args)
{
   char *name, *old_value, *new_value;

   // $HOME: Set to /home/$USER unless --no-home specified.
   if (!args->c.private_home) {
      old_value = getenv("USER");
      if (old_value == NULL) {
         WARNING("$USER not set; cannot rewrite $HOME");
      } else {
         T_ (1 <= asprintf(&new_value, "/home/%s", old_value));
         Z_ (setenv("HOME", new_value, 1));
      }
   }

   // $PATH: Append /bin if not already present.
   old_value = getenv("PATH");
   if (old_value == NULL) {
      WARNING("$PATH not set");
   } else if (   strstr(old_value, "/bin") != old_value
              && !strstr(old_value, ":/bin")) {
      T_ (1 <= asprintf(&new_value, "%s:/bin", old_value));
      Z_ (setenv("PATH", new_value, 1));
      INFO("new $PATH: %s", new_value);
   }

   // --set-env and --unset-env.
   for (int i = 0; args->env_deltas[i].action != ENV_END; i++) {
      char *arg = args->env_deltas[i].arg;
      if (args->env_deltas[i].action == ENV_SET) {  // --set-env
         if (strchr(arg, '=') != NULL) {
            // argument is variable name & value
            envs_set((char *[]){ arg }, 1, NULL, args->c.env_expand);
         } else {
            // argument is filename
            char **lines = NULL;
            int line_ct = 0;
            FILE *fp;
            Tf (fp = fopen(arg, "r"), "--set-env: can't open: %s", arg);
            for (line_ct = 0; true; line_ct++) {
               char *line;
               size_t line_len = 0;  // don't care but getline(3) must write
               errno = 0;
               if (-1 == getline(&line, &line_len, fp)) {
                  if (errno == 0)  // EOF
                     break;        // note: line_ct not incremented
                  else
                     Tf (0, "--set-env: can't read: %s", arg);
               }
               if (line[strlen(line) - 1] == '\n')  // rm newline if present
                  line[strlen(line) - 1] = 0;
               T_ (lines = realloc(lines, (line_ct + 1) * sizeof(char *)));
               lines[line_ct] = line;
            }
            Zf (fclose(fp), "--set-env: can't close: %s", arg);
            envs_set(lines, line_ct, arg, args->c.env_expand);
         }
      } else {  // --unset-env
         T_ (args->env_deltas[i].action == ENV_UNSET);
         /* Removing variables from the environment is tricky, because there
            is no standard library function to iterate through the
            environment, and the environ global array can be re-ordered after
            unsetenv(3) [1]. Thus, the only safe way without additional
            storage is an O(n^2) search until no matches remain.

            It is legal to assign to environ [2]. We build up a copy, omitting
            variables that match the glob, which is O(n), and then do so.

            [1]: https://unix.stackexchange.com/a/302987
            [2]: http://man7.org/linux/man-pages/man3/exec.3p.html */
         char **new_environ;
         int old_i, new_i;
         for (old_i = 0; environ[old_i] != NULL; old_i++)
            ;
         T_ (new_environ = calloc(old_i + 1, sizeof(char *)));
         for (old_i = 0, new_i = 0; environ[old_i] != NULL; old_i++) {
            int matchp;
            split(&name, &old_value, environ[old_i], '=');
            T_ (name != NULL);          // env lines should always have equals
            matchp = fnmatch(arg, name, 0);
            if (!matchp) {
               INFO("environment: unset %s", name);
            } else {
               T_ (matchp == FNM_NOMATCH);
               *(old_value - 1) = '=';  // rejoin line
               new_environ[new_i++] = name;
            }
         }
         environ = new_environ;
      }
   }

   // $CH_RUNNING
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
   case -10: // --env-no-expand
      args->c.env_expand = false;
      break;
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
      args->c.join_pid = parse_int(arg, false, "--join-pid");
      break;
   case -6: // --set-env
      env_delta_append(&(args->env_deltas), ENV_SET, arg);
      break;
   case -7: // --unset-env
      Te (strlen(arg) > 0, "--unset-env: GLOB must have non-zero length");
      env_delta_append(&(args->env_deltas), ENV_UNSET, arg);
      break;;
   case -8: // --ch-ssh
      args->c.ch_ssh = true;
      break;
   case -9: // --no-passwd
      args->c.private_passwd = true;
      break;
   case 'c':
      args->initial_dir = arg;
      break;
   case 'b': {
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
   case 'g':
      i = parse_int(arg, false, "--gid");
      Te (i >= 0, "--gid: must be non-negative");
      args->c.container_gid = (gid_t) i;
      break;
   case 'j':
      args->c.join = true;
      break;
   case 's':
      args->c.sq_mountpt = arg;
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
      Te(verbose <= 4, "--verbose can be specified at most thrice");
      break;
   case 'w':
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
