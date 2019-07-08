BINS := $(patsubst %.c,%,$(wildcard *.c))

.PHONY: all
all: $(BINS)

.PHONY: clean
clean:
	rm -f $(BINS)

$(BINS): Makefile

%: %.c
	gcc $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) $< -o $@
