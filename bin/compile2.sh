#!/bin/bash


gcc -c ch_misc.c -o ch_misc.o -D_FILE_OFFSET_BITS=64 -g -std=c99

gcc -c ch_core.c -I/home/mphinney/squashfuse/ -o ch_core.o -D_FILE_OFFSET_BITS=64 -g -std=c99
#/users/chernikov/squashfuse/.libs/libsquashfuse.a /users/chernikov/squashfuse/.libs/libfuseprivate.a

gcc -c ch-run.c -I/home/mphinney/squashfuse/ -o ch-run.o -D_FILE_OFFSET_BITS=64 -g -std=c99

gcc ch-run.o -llzma /usr/lib64/liblzo2.so.2 /usr/lib64/liblz4.so.1 -lz -lfuse -lpthread -lrt -o ch-run ch_misc.o ch_core.o /home/mphinney/squashfuse/.libs/libsquashfuse.a /home/mphinney/squashfuse/.libs/libfuseprivate.a

