SUBDIRS = lib bin doc examples misc packaging test

# The Travis stuff isn't really relevant for the tarballs, but they should
# have complete source code.
EXTRA_DIST = .travis.yml

EXTRA_DIST += LICENSE README.rst VERSION autogen.sh

TESTS = $(top_builddir)/bin/ch-test
AM_TESTS_ENVIRONMENT = \
  export CH_TEST_PHASE=all; \
  export CH_TEST_IMGDIR=/tmp/ch-test.tmp.${USER}/img; \
  export CH_TEST_TARDIR=/tmp/ch-test.tmp.${USER}/tar;

installcheck-local:
	diff $(top_builddir)/lib/version.txt $(ch_libdir)/version.txt
	$(DESTDIR)$(bindir)/ch-test all -b none \
		--pack-dir=/tmp/ch-test.tmp.${USER}/tar \
		--img-dir=/tmp/ch-test.tmp.${USER}/img;
