BINS := chroot-escape echo-euid mknods setgroups setuid
ALL := $(BINS)
CFLAGS := -std=gnu11 -Wall

.PHONY: all
all: $(ALL)

.PHONY: clean
clean:
	rm -f $(ALL)
