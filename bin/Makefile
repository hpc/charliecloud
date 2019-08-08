bin := ch-run ch-ssh ch-checkns ch-ranch
src := ch-run.c ch-ssh.c ch-ranch.c
obj := $(src:.c=.o)

CFLAGS += -pthread
LDLIBS += -pthread -lrt

.PHONY: all
all: $(bin)

$(obj): charliecloud.h version.h Makefile
$(bin): charliecloud.o

.PHONY: clean
clean:
	rm -Rf *.o $(bin)
