#!/bin/bash

# Demonstrate that MPI works in C and Python.
#
# Requires ./data as first --dir.

if [ "$CH_GUEST_ID" != 0 ]; then
    echo 'not guest 0; waiting for work'
    exit 0
fi

cd /ch/data1

echo "Are we running on all nodes?"
mpirun hostname

echo
echo "Can we do MPI in C?"
mpicc hello.c
mpirun ./a.out

echo
echo "Can we do MPI in Python?"
mpirun ./hello.py
