/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "config.h"
#include "ch_misc.h"


const char usage[] = "\
\n\
Usage: CH_RUN_ARGS=\"NEWROOT [ARG...]\" ch-ssh [OPTION...] HOST CMD [ARG...]\n\
\n\
Run a remote command in a Charliecloud container.\n\
\n\
Example:\n\
\n\
  $ export CH_RUN_ARGS=/data/foo\n\
  $ ch-ssh example.com -- echo hello\n\
  hello\n\
\n\
Arguments to ch-run, including the image to activate, are specified in the\n\
CH_RUN_ARGS environment variable. Important caveat: Words in CH_RUN_ARGS are\n\
delimited by spaces only; it is not shell syntax. In particular, quotes and\n\
and backslashes are not interpreted.\n";

#define ARGS_MAX 262143  // assume 2MB buffer and length of each argument >= 7


int main(int argc, char *argv[])
{
   int i, j;
   char *ch_run_args;
   char *args[ARGS_MAX+1];

   if (argc == 1) {
      fprintf(stderr, usage);
      exit(EXIT_FAILURE);
   }
   if (argc >= 2 && strcmp(argv[1], "--help") == 0) {
      fprintf(stderr, usage);
      return 0;
   }
   if (argc >= 2 && strcmp(argv[1], "--version") == 0) {
      version();
      exit(EXIT_SUCCESS);
   }

   memset(args, 0, sizeof(args));
   args[0] = "ssh";

   // ssh option arguments
   for (i = 1; i < argc && i < ARGS_MAX && argv[i][0] == '-'; i++)
      args[i] = argv[i];

   // destination host
   if (i < argc && i < ARGS_MAX) {
      args[i] = argv[i];
      i++;
   }

   // insert ch-run command
   ch_run_args = getenv("CH_RUN_ARGS");
   Te (ch_run_args != NULL, "CH_RUN_ARGS not set");

   args[i] = "ch-run";
   for (j = 1; i + j < ARGS_MAX; j++, ch_run_args = NULL) {
      args[i+j] = strtok(ch_run_args, " ");
      if (args[i+j] == NULL)
         break;
   }

   // copy remaining arguments
   for ( ; i < argc && i + j < ARGS_MAX; i++)
      args[i+j] = argv[i];

   execvp("ssh", args);
   Tf (0, "can't execute ssh");
}
