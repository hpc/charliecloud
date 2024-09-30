# Bugs in this Makefile:
#
# 1. $(EXEEXT) not included for scripts.

## C programs

bin_PROGRAMS = ch-checkns ch-run

ch_checkns_SOURCES = ch-checkns.c mem.h mem.c misc.h misc.c

ch_run_SOURCES = ch-run.c core.h core.c hook.h hook.c mem.h mem.c misc.h misc.c
if HAVE_JSON
ch_run_SOURCES += json.h json.c
endif
if HAVE_LIBSQUASHFUSE
ch_run_SOURCES += fuse.h fuse.c
endif
if HAVE_SECCOMP
ch_run_SOURCES += seccomp.h seccomp.c
endif


## Shell scripts - distributed as-is

dist_bin_SCRIPTS = ch-convert \
                   ch-fromhost \
                   ch-test


## Python scripts - need text processing

bin_SCRIPTS = ch-run-oci  # scripts to build
EXTRA_SCRIPTS = ch-image  # more scripts that *may* be built
if ENABLE_CH_IMAGE
bin_SCRIPTS += ch-image
endif
EXTRA_DIST = ch-image.py.in ch-run-oci.py.in
CLEANFILES = $(bin_SCRIPTS) $(EXTRA_SCRIPTS)

ch-image: ch-image.py.in
ch-run-oci: ch-run-oci.py.in

$(bin_SCRIPTS): %: %.py.in
	rm -f $@
	sed -E 's|%PYTHON_SHEBANG%|@PYTHON_SHEBANG@|' < $< > $@
	chmod +rx,-w $@  # respects umask
