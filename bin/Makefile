# Default target. This should depend on binaries you actually want to deploy.
.PHONY: default
default: all

# All binaries. This is everything, including testing stuff that you don't
# want users to have.
bins_all := ch-run

# Add some good stuff to CFLAGS.
CFLAGS += -std=c11 -Wall -Werror -Wfatal-errors

.PHONY: all
all: $(bins_all)

.PHONY: clean
clean:
	rm -Rf $(bins_all)

%: %.c
	$(CC) $(CFLAGS) -o $@ $<
