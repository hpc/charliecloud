#!/bin/bash

#################################################################################
# A quick compile script for Woodchuck cluster environment                      #
#################################################################################

SQFUSE_HEADERS=$HOME/squashfuse/
CPPFLAGS=" -I"$SQFUSE_HEADERS""
CFLAGS="-std=c99 -D_FILE_OFFSET_BITS=64 -g"
LIBS="-llzma -llzo2 -llz4 -lz -lfuse -lpthread -lrt"
SQFUSE_LIBS=""$HOME"/squashfuse/.libs/libsquashfuse.a "$HOME"/squashfuse/.libs/libfuseprivate.a"
gcc -c ch_misc.c -o ch_misc.o $CFLAGS

gcc -c ch_core.c $CPPFLAGS -o ch_core.o $CFLAGS

gcc -c ch-run.c $CPPFLAGS -o ch-run.o $CFLAGS

gcc ch-run.o $LIBS -o ch-run ch_misc.o ch_core.o $SQFUSE_LIBS
