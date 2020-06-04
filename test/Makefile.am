testdir = $(pkglibexecdir)/test
topbindir = $(top_builddir)/bin

# These test files require no special handling.
testfiles = \
Dockerfile.00_tiny \
Dockerfile.argenv \
Dockerfile.build2dir \
build/10_sanity.bats \
build/50_ch-tug.bats \
build/50_dockerfile.bats \
build/50_misc.bats \
build/99_cleanup.bats \
common.bash \
make-auto.d/build.bats.in \
make-auto.d/build_custom.bats.in \
make-auto.d/builder_to_archive.bats.in \
make-auto.d/unpack.bats.in \
run/build-rpms.bats \
run/ch-fromhost.bats \
run/ch-run_escalated.bats \
run/ch-run_isolation.bats \
run/ch-run_join.bats \
run/ch-run_misc.bats \
run/ch-run_uidgid.bats \
run/ch-tar2dir.bats \
run_first.bats \
sotest/files_inferrable.txt \
sotest/libsotest.c \
sotest/sotest.c

# Test files that should be executable.
testfiles_exec = \
Build.centos7xz \
Build.ch-build2dir \
Build.ch-pull2dir \
Build.ch-pull2tar \
Build.docker_pull \
Build.missing \
ch-test.make \
docs-sane \
make-perms-test

# Stuff that doesn't need to be installed.
EXTRA_DIST = \
fixtures/README \
travis.bash \
travis-before.bash \
travis-install.bash \
travis.yml

# Program and shared library used for testing shared library injection. It's
# built according to the rules below. In principle, we could use libtool for
# that, but I'm disinclined to add that in since it's one test program and
# does not require any libtool portability.
sobuilts = \
sotest/bin/sotest \
sotest/lib/libsotest.so.1.0 \
sotest/libsotest.so \
sotest/libsotest.so.1 \
sotest/libsotest.so.1.0 \
sotest/sotest

# FIXME: if a test fails bats simply reports that the test fails, i.e., bats
# doesn't return a nonzero unless something funky happened. We need to
# make the 'make check' error if a test fails.
TESTS = ch-test.make

# Note because we cannot pass a script declared in TESTS any arguments, we are
# forced to use a wrapper script, ch-test.make, to specify a phase to ch-test.
# Thus, using AM_TESTS_ENVIRONMENT doesn't seem all that useful and is commented
# out.
#
# AM_TESTS_ENVIRONMENT = \
#	$(TESTS); \
#	CH_TEST_IMGDIR=/tmp/ch-test.tmp.${USER}/img; export CH_TEST_IMGDIR; \
#	CH_TEST_TARDIR=/tmp/ch-test.tmp.${USER}/tar; export CH_TEST_TARDIR;

if ENABLE_TEST
nobase_test_DATA = $(testfiles)
nobase_test_SCRIPTS = $(testfiles_exec)
nobase_nodist_test_SCRIPTS = $(sobuilts)
CLEANFILES = $(sobuilts) docs-sane make-perms-test
# See comment about symlinks in examples/Makefile.am.
all-local:
	ln -fs /tmp fixtures/symlink-to-tmp
clean-local:
	rm -f fixtures/symlink-to-tmp
install-data-hook:
	mkdir $(DESTDIR)$(testdir)/fixtures
	ln -fs /tmp $(DESTDIR)$(testdir)/fixtures/symlink-to-tmp

# FIXME: if a test fails bats simply reports that the test fails, i.e., bats
# doesn't return a nonzero unless something funky happened. We need to
# make the installcheck error if a test fails.
installcheck-local:
	$(topbindir)/ch-test build -b none \
		--pack-dir=/tmp/ch-test.tmp.${USER}/tar \
        --img-dir=/tmp/ch-test.tmp.${USER}/img; \
	$(topbindir)/ch-test run -b none \
		--pack-dir=/tmp/ch-test.tmp.${USER}/tar \
        --img-dir=/tmp/ch-test.tmp.${USER}/img

uninstall-hook:
	rm -f $(DESTDIR)$(testdir)/fixtures/symlink-to-tmp
	rmdir $(DESTDIR)$(testdir)/fixtures || true
endif
EXTRA_DIST += $(testfiles) $(testfiles_exec) docs-sane.py.in make-perms-test.py.in
EXTRA_SCRIPTS = $(sobuilts)

## Python scripts - need text processing
docs-sane make-perms-test: %: %.py.in
	sed -E 's|%PYTHON_SHEBANG%|@PYTHON_SHEBANG@|' < $< > $@
	chmod +rwx $@  # respects umask

sotest/sotest: sotest/sotest.c sotest/libsotest.so.1.0 sotest/libsotest.so sotest/libsotest.so.1
	$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -L./sotest -lsotest $^
sotest/libsotest.so.1.0: sotest/libsotest.c
	$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -shared -fPIC -Wl,-soname,libsotest.so.1 -lc $^

sotest/libsotest.so: sotest/libsotest.so.1.0
	ln -f -s ./libsotest.so.1.0 $@
sotest/libsotest.so.1: sotest/libsotest.so.1.0
	ln -f -s ./libsotest.so.1.0 $@

sotest/bin/sotest: sotest/sotest
	mkdir -p sotest/bin
	cp -a $^ $@
sotest/lib/libsotest.so.1.0: sotest/libsotest.so.1.0
	mkdir -p sotest/lib
	cp -a $^ $@
