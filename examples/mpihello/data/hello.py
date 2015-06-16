#!/usr/bin/python2.7

# Based on examples in https://www.tacc.utexas.edu/c/document_library/get_file?uuid=be16db01-57d9-4422-b5d5-17625445f351

from __future__ import division
from __future__ import print_function

from mpi4py import MPI
from pprint import pprint

comm = MPI.COMM_WORLD
size = comm.Get_size()
rank = comm.Get_rank()
name = MPI.Get_processor_name()

foo = set((8, 6, 7))  # let's try a fancy Python data type

if (rank == 0):
   result = dict()
   for r in xrange(1, size):
      comm.send(foo, dest=r)
   for r in xrange(1, size):
      result[r] = comm.recv(source=r)
   print('%d workers finished, result on rank 0 is:' % (size - 1))
   pprint(result)
else:
   bar = comm.recv(source=0)
   comm.send(bar.union((5, 3, 0, 9, 'rank %d on %s' % (rank, name))), dest=0)
