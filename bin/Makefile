# Default target. This should depend on binaries you actually want to deploy.
.PHONY: default
default: ch-run.ns

# All binaries. This is everything, including testing stuff that you don't
# want users to have.
bins_all=ch-run.chroot ch-run.ns ch-run.ns.unsafe

.PHONY: all
all: $(bins_all)

.PHONY: clean
clean:
	rm -Rf $(bins_all)

%: %.c
	$(CC) -std=c11 $(CFLAGS) -o $@ $<
	sudo chown root $@
	sudo chmod u+s $@

%.unsafe: %.c
	$(CC) -std=c11 $(CFLAGS) -D NO_DROP_PRIVS -o $@ $<
