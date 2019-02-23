bin := ch-run ch-ssh
src := $(wildcard *.c)
obj := $(src:.c=.o)

CFLAGS += -pthread
LDLIBS += -pthread -lrt

.PHONY: all
all: $(bin)

$(obj): charliecloud.h version.h Makefile
$(bin): charliecloud.o
ch-slurm.so: ch-slurm.c charliecloud.c charliecloud.h
	gcc -std=c11 -shared -fPIC -DSPANKPLUGIN -o ch-slurm.so ch-slurm.c charliecloud.c

.PHONY: clean
clean:
	rm -Rf *.o $(bin)
