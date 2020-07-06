#CC=gcc
#CPPFLAGS=-I$(HOME)/squashfuse/
#CFLAGS=-D_FILE_OFFSET_BITS=64 -v
#LDFLAGS=-L$(HOME)/squashfuse/.libs -L/usr/lib64

#LIBS=-lsquashall -llzma -lzo2 -llz4 -lz

all: test

test: test.o
	gcc test.o -llzo2 -lz -llz4 -llzma -lfuse -o test /users/chernikov/squashfuse/.libs/libsquashfuse.a /users/chernikov/squashfuse/.libs/libfuseprivate.a -v 
test.o: test.c
	gcc -g -c test.c -I/users/chernikov/squashfuse/ -o test.o -D_FILE_OFFSET_BITS=64
