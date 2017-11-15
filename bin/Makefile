bin := ch-run ch-ssh
src := $(wildcard *.c)
obj := $(src:.c=.o)

.PHONY: all
all: $(bin)

$(obj): charliecloud.h Makefile
$(bin): charliecloud.o

.PHONY: clean
clean:
	rm -Rf *.o $(bin)

ifdef SETUID
export CFLAGS += -DSETUID
all: setuid
setuid: ch-run
#	Use sudo only if not already root.
	if [ $$(id -u) -eq 0 ]; then \
	    chown root $<; \
	    chmod u+s $<; \
	elif ( command -v sudo >/dev/null 2>&1 && sudo -v >/dev/null 2>&1 ); then \
	    sudo chown root $<; \
	    sudo chmod u+s $<; \
	fi
endif
