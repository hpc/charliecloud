PROGS := chroot-escape echo-euid mknods setgroups
SETUIDS := echo-euid.setuid
ALL := $(PROGS) $(SETUIDS)
CFLAGS := -std=gnu11 -Wall

.PHONY: all clean
all: $(ALL)
clean:
	rm -f $(ALL)
$(ALL): Makefile

%: %.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@
	chmod 755 $@

%.setuid: %
	cp $< $@
	sudo chown root:root $@
	sudo chmod 4755 $@
