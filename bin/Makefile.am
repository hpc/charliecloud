
# VERSION.full contains the version string reported by executables; see FAQ.
# Needs to be converted to an AM_CONDITIONAL
#ifeq ($(shell test -d .git && fgrep -q \~ VERSION && echo true),true)
#.PHONY: VERSION.full  # depends on git metadata, not a simple file
#VERSION.full: VERSION
#    #(git --version > /dev/null 2>&1) || \
#    #      (echo "This is a Git working directory but no git found." && false)
#	printf '%s+%s%s%s\n' \
#           $$(cat $<) \
#           $$(  git rev-parse --abbrev-ref HEAD \
#              | sed 's/[^A-Za-z0-9]//g' \
#              | sed 's/$$/./g' \
#              | sed 's/master.//g') \
#           $$(git rev-parse --short HEAD) \
#           $$(git diff-index --quiet HEAD || echo '.dirty') \
#           > $@
#else
#VERSION.full: VERSION
#    cp $< $@
#endif

#bin/version.h: VERSION.full
#	echo "#define VERSION \"$$(cat $<)\"" > $@
#bin/version.sh: VERSION.full
#	echo "version () { echo 1>&2 '$$(cat $<)'; }" > $@


AM_CXXFLAGS = -g -Wall
AM_LDFLAGS = -lpthread

bin_PROGRAMS = ch-checkns ch-run ch-ssh

ch_checkns_SOURCES = ch-checkns.c charliecloud.c
ch_run_SOURCES = ch-run.c charliecloud.c
ch_ssh_SOURCES = ch-ssh.c charliecloud.c
