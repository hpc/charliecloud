# Default target. This should depend on binaries you actually want to deploy.
.PHONY: default
default: ch-run.ns

# All binaries. This is everything, including testing stuff that you don't
# want users to have.
bins_all=ch-run.ns ch-run.ns.no_user_ns ch-run.ns.run_as_root

.PHONY: all
all: $(bins_all)

.PHONY: clean
clean:
	rm -Rf $(bins_all)

%: %.c
	$(CC) -std=c11 -Wall -Werror -Wfatal-errors $(CFLAGS) -o $@ $<

%.no_user_ns: %.c
	$(CC) -std=c11 $(CFLAGS) -D NO_USER_NS -o $@ $<

%.run_as_root: %.c
	$(CC) -std=c11 $(CFLAGS) -D RUN_AS_ROOT -o $@ $<
