if ENABLE_TEST

testdir = $(pkglibexecdir)/test

# Note: All these are under "SCRIPTS" because I couldn't come up with a better
# primary, and Automake complained about DATA.

# These test files require no special handling.
nobase_test_SCRIPTS = \
build.bats \
build_post.bats \
chtest-make-auto \
common.bash \
docs-sane \
make-auto.d/build.bats.in \
make-auto.d/build_custom.bats.in \
make-auto.d/builder_to_archive.bats.in \
make-auto.d/run_image.bats.in \
make-auto.d/unpack.bats.in \
make-perms-test \
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
sotest/sotest.c \
travis.bash \
travis-before.bash \
travis-install.bash \
travis.yml

# Program and shared library used for testing shared library injection. It's
# built according to the rules below. In principle, we could use libtool for
# that, but I'm disinclined to add that in since it's one test program and
# does not require any libtool portability.
nobase_nodist_test_SCRIPTS = \
sotest/bin/sotest \
sotest/lib/libsotest.so.1.0 \
sotest/libsotest.so \
sotest/libsotest.so.1 \
sotest/libsotest.so.1.0 \
sotest/sotest

CLEANFILES = $(nobase_nodist_test_SCRIPTS)

#all-local: $(nobase_nodist_test_SCRIPTS)

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

endif
