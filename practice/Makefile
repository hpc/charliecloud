#CC=gcc
CPPFLAGS=-I$(HOME)/squashfuse/
CFLAGS=-D_FILE_OFFSET_BITS=64 -g
STATIC_LIBS=$(HOME)/squashfuse/.libs/libsquashfuse.a $(HOME)/squashfuse/.libs/libfuseprivate.a

LIBS=-llzma -llzo2 -llz4 -lz -lfuse

all: test

test: test.o
	$(CC) test.o $(LIBS) -o test $(STATIC_LIBS)
test.o: test.c
	$(CC) -c test.c $(CPPFLAGS) -o test.o $(CFLAGS)
clean:
	-rm test.o test
