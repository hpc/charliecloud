# Define an alias for pkglibdir to override Automake helpfulness:
#
#   error: 'pkglibdir' is not a legitimate directory for 'DATA'
#
# See: https://www.gnu.org/software/automake/manual/html_node/Uniform.html
mylibdir = $(pkglibdir)

dist_mylib_DATA = base.sh \
                  build.py \
                  charliecloud.py \
                  fakeroot.py \
                  misc.py \
                  pull.py \
                  push.py \
		  python_modules

noinst_DATA = charliecloud
mylib_DATA = contributors.bash \
             version.py \
             version.sh \
             version.txt

CLEANFILES = $(mylib_DATA) $(noinst_DATA)

# This symlink is so scripts can use "lib/charliecloud" whether they are
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
