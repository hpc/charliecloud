CC=gcc
CFLAGS=-I $(HOME)/squashfuse/ -D_FILE_OFFSET_BITS=64 -v

LDIR=$(HOME)/squashfuse/.libs/

LIBS=-lsquashall -llzma -lzo2 -llz4 -lz

testmake: test
	$(CC) -o test test.c $(CFLAGS) $(LIBS)
