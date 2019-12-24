/* MPI test program. Reports user namespace and rank, then sends and receives
   some simple messages.

   Patterned after:
   http://en.wikipedia.org/wiki/Message_Passing_Interface#Example_program */

#define _GNU_SOURCE
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <mpi.h>

#define TAG 0
#define MSG_OUT 8675309

void fatal(char * fmt, ...);
int op(int rank, int i);

int rank, rank_ct;

int main(int argc, char ** argv)
{
   char hostname[HOST_NAME_MAX+1];
   char mpi_version[MPI_MAX_LIBRARY_VERSION_STRING];
   int mpi_version_len;
   int msg;
   MPI_Status mstat;
   struct stat st;

   stat("/proc/self/ns/user", &st);

   MPI_Init(&argc, &argv);
   MPI_Comm_size(MPI_COMM_WORLD, &rank_ct);
   MPI_Comm_rank(MPI_COMM_WORLD, &rank);

   if (rank == 0) {
      MPI_Get_library_version(mpi_version, &mpi_version_len);
      printf("%d: MPI version:\n%s\n", rank, mpi_version);
   }

   gethostname(hostname, HOST_NAME_MAX+1);
   printf("%d: init ok %s, %d ranks, userns %lu\n",
          rank, hostname, rank_ct, st.st_ino);
   fflush(stdout);

   if (rank == 0) {
      for (int i = 1; i < rank_ct; i++) {
         msg = MSG_OUT;
         MPI_Send(&msg, 1, MPI_INT, i, TAG, MPI_COMM_WORLD);
         msg = 0;
         MPI_Recv(&msg, 1, MPI_INT, i, TAG, MPI_COMM_WORLD, &mstat);
         if (msg != op(i, MSG_OUT))
            fatal("0: expected %d back but got %d", op(i, MSG_OUT), msg);
      }
   } else {
      msg = 0;
      MPI_Recv(&msg, 1, MPI_INT, 0, TAG, MPI_COMM_WORLD, &mstat);
      if (msg != MSG_OUT)
         fatal("%d: expected %d but got %d", rank, MSG_OUT, msg);
      msg = op(rank, msg);
      MPI_Send(&msg, 1, MPI_INT, 0, TAG, MPI_COMM_WORLD);
   }

   if (rank == 0)
      printf("%d: send/receive ok\n", rank);

   MPI_Finalize();
   if (rank == 0)
      printf("%d: finalize ok\n", rank);
   return 0;
}

void fatal(char * fmt, ...)
{
   va_list ap;

   fprintf(stderr, "rank %d:", rank);

   va_start(ap, fmt);
   vfprintf(stderr, fmt, ap);
   va_end(ap);

   fprintf(stderr, "\n");
   exit(EXIT_FAILURE);
}

int op(int rank, int i)
{
   return i * rank;
}
