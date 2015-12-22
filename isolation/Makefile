PROGS := chroot-escape echo-euid
SETUIDS := echo-euid.setuid
ALL := $(PROGS) $(SETUIDS)
CFLAGS := -std=gnu11

.PHONY: all clean
all: $(ALL)
clean:
	rm -f $(ALL)
$(ALL): Makefile

%: %.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@

%.setuid: %
	cp $< $@
	chown root:root $@
	chmod 4755 $@
