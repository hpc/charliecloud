CC=gcc
CPPFLAGS=-I$(HOME)/squashfuse/
CFLAGS=-D_FILE_OFFSET_BITS=64 -v
LDFLAGS=-L$(HOME)/squashfuse/.libs -L/usr/lib64

LIBS=-lsquashall -llzma -lzo2 -llz4 -lz

testmake: test
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) test.c -o test $(LIBS)
