testdir = $(pkglibexecdir)/test

# These test files require no special handling.
testfiles = \
Dockerfile.argenv \
Dockerfile.build2dir \
build.bats \
build_post.bats \
common.bash \
make-auto.d/build.bats.in \
make-auto.d/build_custom.bats.in \
make-auto.d/builder_to_archive.bats.in \
make-auto.d/run_image.bats.in \
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
Build.skopeo-umoci \
chtest-make-auto \
docs-sane \
make-perms-test

# Travis stuff doesn't need to be installed.
EXTRA_DIST = \
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

if ENABLE_TEST
nobase_test_DATA = $(testfiles)
nobase_test_SCRIPTS = $(testfiles_exec)
nobase_nodist_test_SCRIPTS = $(sobuilts)
CLEANFILES = $(sobuilts)
endif
EXTRA_DIST += $(testfiles) $(testfiles_exec)
EXTRA_SCRIPTS = $(sobuilts)

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
