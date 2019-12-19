# FIXME:
#
# 1. SCRIPTS makes all this stuff executable when it shouldn't be, but
#    Automake complains that DATA can't go in libexecdir.

dist_pkglibexec_SCRIPTS = base.sh
noinst_DATA = charliecloud
pkglibexec_SCRIPTS = version.py version.sh version.txt

CLEANFILES = $(pkglibexec_SCRIPTS) $(noinst_DATA)

# This symlink is so scripts can use "libexec/charliecloud" whether they are
# installed or not.
charliecloud:
	ln -s . charliecloud

version.txt: ../configure
	printf '@PACKAGE_VERSION@\n' > $@

version.py: ../configure
	printf "VERSION='@PACKAGE_VERSION@'\n" > $@

version.sh: ../configure
	printf "# shellcheck disable=SC2034\n" > $@
	printf "ch_version='@PACKAGE_VERSION@'\n" >> $@
