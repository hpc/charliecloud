#!/bin/bash


gcc -c ch_misc.c -o ch_misc.o -D_FILE_OFFSET_BITS=64 -g -std=c99

gcc -c ch_core.c -I/users/chernikov/squashfuse/ -o ch_core.o -D_FILE_OFFSET_BITS=64 -g -std=c99
#/users/chernikov/squashfuse/.libs/libsquashfuse.a /users/chernikov/squashfuse/.libs/libfuseprivate.a

gcc -c ch-run.c -I/users/chernikov/squashfuse/ -o ch-run.o -D_FILE_OFFSET_BITS=64 -g -std=c99

gcc ch-run.o -llzma -llzo2 -llz4 -lz -lfuse -lpthread -lrt -o ch-run ch_misc.o ch_core.o /users/chernikov/squashfuse/.libs/libsquashfuse.a /users/chernikov/squashfuse/.libs/libfuseprivate.a

