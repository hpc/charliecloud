dist_libexec_SCRIPTS = base.sh
EXTRA_DIST = charliecloud

libexec_SCRIPTS = version.py version.sh

CLEANFILES = $(libexec_SCRIPTS) version.full


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
