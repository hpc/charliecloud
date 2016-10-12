bin := ch-run ch-ssh
src := $(wildcard *.c)
obj := $(src:.c=.o)

# Add some good stuff to CFLAGS.
CFLAGS += -std=c11 -Wall

.PHONY: all
all: $(bin)

$(obj): charliecloud.h Makefile
$(bin): charliecloud.o

.PHONY: clean
clean:
	rm -Rf *.o $(bin)


