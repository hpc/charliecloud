SUBDIRS = lib bin doc examples misc packaging test

# The CI stuff isn't really relevant for the tarballs, but they should
# have complete source code.
EXTRA_DIST = .github/PERUSEME .github/workflows/main.yml

EXTRA_DIST += LICENSE README.rst VERSION autogen.sh

# Embedded paths are in the source code suitable for running from the source
# directory (i.e., without install). When installing, those paths are often
# wrong, so re-write them with the correct paths we got from configure. Note:
# Some variables are in both Python and sh, so we use syntax valid for both;
# others are just sh.
install-exec-hook:
	@echo '### re-writing embedded paths ###'
	for i in @bindir@/ch-convert \
	         @bindir@/ch-fromhost \
	         @bindir@/ch-image \
	         @bindir@/ch-run-oci \
	         @bindir@/ch-test \
	         @libdir@/charliecloud/base.sh; \
	do \
	  sed -Ei -e 's|^(ch_lib ?= ?).+/lib"?$$|\1"@libdir@/charliecloud"|' \
	          -e 's|^(CHTEST_DIR=).+$$|\1@libexecdir@/charliecloud/test|' \
	          -e 's|^(CHTEST_EXAMPLES_DIR=).+$$|\1@docdir@/examples|' \
              $$i; \
	done

#bindir: @bindir@
#	echo libdir: @libdir@
#	echo libexecdir: @libexecdir@
