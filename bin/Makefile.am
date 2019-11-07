dist_bin_SCRIPTS =
CLEANFILES =
EXTRA_DIST =

## C programs

bin_PROGRAMS = ch-checkns ch-run ch-ssh

ch_checkns_SOURCES = ch-checkns.c ch_misc.h ch_misc.c

ch_run_SOURCES = ch-run.c ch_misc.h ch_core.c ch_misc.h ch_misc.c
ch_run_CFLAGS = $(CFLAGS) $(PTHREAD_CFLAGS)
ch_run_LDFLAGS = $(AM_LDFLAGS) $(LIBRT)

ch_ssh_SOURCES = ch-ssh.c ch_misc.h ch_misc.c


## Shell scripts - distributed as-is

# FIXME: $(EXEEXT) not included for scripts.



## Python scripts - need text processing

python_scripts = ch-grow ch-run-oci
EXTRA_DIST += ch-grow.py.in ch-run-oci.py.in

CLEANFILES += $(python_scripts)
dist_bin_SCRIPTS += $(python_scripts)

ch-grow: ch-grow.py.in
ch-run-oci: ch-run-oci.py.in

$(dist_bin_SCRIPTS): %: %.py.in
	sed -E 's|%PYTHON_SHEBANG%|@PYTHON_SHEBANG@|' < $< > $@
	chmod +rwx $@  # respects umask
