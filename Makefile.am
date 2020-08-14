ch_libdir = $(DESTDIR)$(libdir)/charliecloud

SUBDIRS = lib bin doc examples misc packaging test

# The Travis stuff isn't really relevant for the tarballs, but they should
# have complete source code.
EXTRA_DIST = .travis.yml

EXTRA_DIST += LICENSE README.rst VERSION autogen.sh

override distcheck:
	tar -xf $(distdir).tar.gz
	cd $(distdir) && ./configure \
	              && $(MAKE) \
	              && ./bin/ch-test all;
	tar -xf $(distdir).tar.gz
	cd $(distdir) && ./autogen.sh \
	              && ./configure --prefix=$(abs_top_builddir)/$(distdir)/prefix \
	              && $(MAKE) install \
	              && $(MAKE) installcheck;
	rm -rf $(distdir)

installcheck-local:
	diff $(top_builddir)/lib/version.txt $(ch_libdir)/version.txt
	$(DESTDIR)$(bindir)/ch-test all \
		--pack-dir=/tmp/ch-test.tmp.${USER}/tar \
		--img-dir=/tmp/ch-test.tmp.${USER}/img;
