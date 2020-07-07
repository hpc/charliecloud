CC=gcc
CPPFLAGS=-I$(HOME)/squashfuse/
CFLAGS=-D_FILE_OFFSET_BITS=64 -g -std=c99
STATIC_LIBS=$(HOME)/squashfuse/.libs/libsquashfuse.a $(HOME)/squashfuse/.libs/libfuseprivate.a

LIBS=-llzma -llzo2 -llz4 -lz -lfuse -lpthread -lrt

all: ch-run

ch-run: ch-run.o ch_misc.o ch_core.o
	$(CC) ch-run.o $(LIBS) -o ch-run ch_misc.o ch_core.o $(STATIC_LIBS)
ch-run.o: ch-run.c
	$(CC) -c ch-run.c $(CPPFLAGS) -o ch-run.o $(CFLAGS)
ch_core.o: ch_core.c
	$(CC) -c ch_core.c $(CPPFLAGS) -o ch_core.c $(CFLAGS)
ch_misc.o: ch_misc.c
	$(CC) -c ch_misc.c -o ch_misc.o $(CFLAGS)
clean:
	-rm ch_core.o ch_misc.o ch-run.o
