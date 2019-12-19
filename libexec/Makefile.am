# FIXME:
#
# 1. Charliecloud isn't a script, but Automake won't let us call it DATA.
#
# 2. SCRIPTS makes all this stuff executable when it shouldn't be, but
#    Automake complains that DATA can't go in libexecdir.

dist_pkglibexec_SCRIPTS = charliecloud base.sh

pkglibexec_SCRIPTS = version.py version.sh

CLEANFILES = $(pkglibexec_SCRIPTS) version.full


version.full: ../VERSION ../misc/version
	../misc/version | tr -d '\n' > $@

version.py: version.full
	truncate -s0 $@
	printf "VERSION='" >> $@
	cat version.full >> $@
	printf "'\n" >> $@

version.sh: version.full
	truncate -s0 $@
	printf "# shellcheck disable=SC2034\n" >> $@
	printf "ch_version='" >> $@
	cat version.full >> $@
	printf "'\n" >> $@
