bin_PROGRAMS = ch-checkns ch-run ch-ssh

ch_checkns_SOURCES = ch-checkns.c ch_misc.h ch_misc.c

ch_run_SOURCES = ch-run.c ch_misc.h ch_core.c ch_misc.h ch_misc.c
ch_run_CFLAGS = $(CFLAGS) $(PTHREAD_CFLAGS)
ch_run_LDFLAGS = $(AM_LDFLAGS) $(LIBRT)

ch_ssh_SOURCES = ch-ssh.c ch_misc.h ch_misc.c
