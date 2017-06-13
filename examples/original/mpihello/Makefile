BINS := hello
CFLAGS := -std=gnu11 -Wall

.PHONY: all
all: $(BINS)

.PHONY: clean
clean:
	rm -f $(BINS)

$(BINS): Makefile

%: %.c
	mpicc $(CFLAGS) $< -o $@
