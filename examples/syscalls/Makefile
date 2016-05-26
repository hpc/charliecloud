BINS := $(patsubst %.c,%,$(wildcard *.c))
CFLAGS := -std=gnu11 -Wall

.PHONY: all
all: $(BINS)

.PHONY: clean
clean:
	rm -f $(BINS)

$(BINS): Makefile

%: %.c
	gcc $(CFLAGS) $< -o $@
