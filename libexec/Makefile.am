# FIXME:
#
# 1. SCRIPTS makes all this stuff executable when it shouldn't be, but
#    Automake complains that DATA can't go in libexecdir.

dist_pkglibexec_SCRIPTS = charliecloud.py base.sh
noinst_DATA = charliecloud
pkglibexec_SCRIPTS = contributors.bash version.py version.sh version.txt

CLEANFILES = $(pkglibexec_SCRIPTS) $(noinst_DATA)

# This symlink is so scripts can use "libexec/charliecloud" whether they are
# installed or not.
charliecloud:
	ln -s . charliecloud

contributors.bash: ../README.rst
	rm -f $@
	printf '# shellcheck shell=bash\n' >> $@
	printf 'declare -a ch_contributors\n' >> $@
	sed -En 's/^\*.+<(.+@.+)>.*$$/ch_contributors+=('"'"'\1'"'"')/p' < $< >> $@

version.txt: ../configure
	printf '@PACKAGE_VERSION@\n' > $@

version.py: ../configure
	printf "VERSION='@PACKAGE_VERSION@'\n" > $@

version.sh: ../configure
	printf "# shellcheck shell=sh disable=SC2034\n" > $@
	printf "ch_version='@PACKAGE_VERSION@'\n" >> $@
