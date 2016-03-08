/* MPI test program. Reports user namespace and rank, then sends and receives
   some simple messages.

   Patterned after:
   http://en.wikipedia.org/wiki/Message_Passing_Interface#Example_program */

#define _GNU_SOURCE
#include <stdio.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <mpi.h>

#define TAG 0

int main(int argc, char ** argv)
{
   int msg, rank, rank_ct;
   struct stat st;
   MPI_Status mstat;

   stat("/proc/self/ns/user", &st);

   MPI_Init(&argc, &argv);
   MPI_Comm_size(MPI_COMM_WORLD, &rank_ct);
   MPI_Comm_rank(MPI_COMM_WORLD, &rank);

   printf("%d: init ok, %d ranks, userns %lu\n", rank, rank_ct, st.st_ino);
   fflush(stdout);

   if (rank == 0) {
      for (int i = 1; i < rank_ct; i++) {
         msg = i;
         MPI_Send(&msg, 1, MPI_INT, i, TAG, MPI_COMM_WORLD);
         //printf("%d: sent msg=%d\n", rank, msg);
         MPI_Recv(&msg, 1, MPI_INT, i, TAG, MPI_COMM_WORLD, &mstat);
         //printf("%d: received msg=%d\n", rank, msg);
      }
   } else {
      MPI_Recv(&msg, 1, MPI_INT, 0, TAG, MPI_COMM_WORLD, &mstat);
      //printf("%d: received msg=%d\n", rank, msg);
      msg = -rank;
      MPI_Send(&msg, 1, MPI_INT, 0, TAG, MPI_COMM_WORLD);
      //printf("%d: sent msg=%d\n", rank, msg);
   }

   if (rank == 0)
      printf("%d: send/receive ok\n", rank);

   MPI_Finalize();
   if (rank == 0)
      printf("%d: finalize ok\n", rank);
   return 0;
}
