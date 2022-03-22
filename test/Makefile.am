testdir = $(pkglibexecdir)/test

# These test files require no special handling.
testfiles = \
.dockerignore \
Dockerfile.00_tiny \
Dockerfile.argenv \
build/10_sanity.bats \
build/40_pull.bats \
build/50_ch-image.bats \
build/50_dockerfile.bats \
build/50_localregistry.bats \
build/50_misc.bats \
build/99_cleanup.bats \
common.bash \
fixtures/empty-file \
fixtures/README \
make-auto.d/build.bats.in \
make-auto.d/build_custom.bats.in \
make-auto.d/builder_to_archive.bats.in \
make-auto.d/unpack.bats.in \
registry-config.yml \
run/build-rpms.bats \
run/ch-fromhost.bats \
run/ch-run_escalated.bats \
run/ch-run_isolation.bats \
run/ch-run_join.bats \
run/ch-run_misc.bats \
run/ch-run_uidgid.bats \
run_first.bats \
sotest/files_inferrable.txt \
sotest/libsotest.c \
sotest/sotest.c

# Test files that should be executable.
testfiles_exec = \
Build.centos7xz \
Build.docker_pull \
Build.missing \
docs-sane \
make-perms-test

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

CLEANFILES = $(sobuilts) \
             docs-sane force-auto make-perms-test \
             build/61_force-auto.bats

if ENABLE_TEST
nobase_test_DATA = $(testfiles)
nobase_test_SCRIPTS = $(testfiles_exec)
nobase_nodist_test_SCRIPTS = $(sobuilts)
if ENABLE_CH_IMAGE  # this means we have Python
nobase_test_DATA += build/61_force-auto.bats
build/61_force-auto.bats: force-auto
	./$< > $@
endif
# See comment about symlinks in examples/Makefile.am.
all-local:
	ln -fTs /tmp fixtures/symlink-to-tmp
clean-local:
	rm -f fixtures/symlink-to-tmp
install-data-hook:
	$(MKDIR_P) $(DESTDIR)$(testdir)/fixtures
	ln -fTs /tmp $(DESTDIR)$(testdir)/fixtures/symlink-to-tmp
uninstall-hook:
	rm -f $(DESTDIR)$(testdir)/fixtures/symlink-to-tmp
	rmdir $(DESTDIR)$(testdir)/fixtures || true
	rmdir $$(find $(pkglibexecdir) -type d | sort -r)
endif
EXTRA_DIST = $(testfiles) $(testfiles_exec) \
             docs-sane.py.in force-auto.py.in make-perms-test.py.in
EXTRA_SCRIPTS = $(sobuilts)

## Python scripts - need text processing
docs-sane force-auto make-perms-test: %: %.py.in
	rm -f $@
	sed -E 's|%PYTHON_SHEBANG%|@PYTHON_SHEBANG@|' < $< > $@
	chmod +rx,-w $@  # respects umask

sotest/sotest: sotest/sotest.c sotest/libsotest.so.1.0 sotest/libsotest.so sotest/libsotest.so.1
	$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -L./sotest -lsotest $^
sotest/libsotest.so.1.0: sotest/libsotest.c
	$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -shared -fPIC -Wl,-soname,libsotest.so.1 -lc $^

sotest/libsotest.so: sotest/libsotest.so.1.0
	ln -fTs ./libsotest.so.1.0 $@
sotest/libsotest.so.1: sotest/libsotest.so.1.0
	ln -fTs ./libsotest.so.1.0 $@

sotest/bin/sotest: sotest/sotest
	mkdir -p sotest/bin
	cp -a $^ $@
sotest/lib/libsotest.so.1.0: sotest/libsotest.so.1.0
	mkdir -p sotest/lib
	cp -a $^ $@
