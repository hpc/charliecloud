# Bugs in this Makefile:
#
# 1. $(EXEEXT) not included for scripts.

## C programs

bin_PROGRAMS = ch-checkns ch-run

ch_checkns_SOURCES = ch-checkns.c ch_misc.h ch_misc.c

ch_run_SOURCES = ch-run.c ch_core.h ch_core.c ch_misc.h ch_misc.c
if HAVE_LIBSQUASHFUSE
ch_run_SOURCES += ch_fuse.h ch_fuse.c
endif

# additional build flags for ch-run
ch_run_CFLAGS = $(PTHREAD_CFLAGS)
ch_run_LDADD = $(CH_RUN_LIBS)


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
