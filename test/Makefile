export LC_ALL := C
images_ch := chtest/Build \
	         $(sort $(wildcard ./Build.*)) \
	         $(sort $(wildcard ./Dockerfile.*)) \
	         $(sort $(wildcard ./Docker_Pull.*))
images_eg := $(sort $(wildcard ../examples/*/*/Build)) \
	         $(sort $(wildcard ../examples/*/*/Build.*)) \
	         $(sort $(wildcard ../examples/*/*/Dockerfile)) \
	         $(sort $(wildcard ../examples/*/*/Dockerfile.*)) \
	         $(sort $(wildcard ../examples/*/*/Docker_Pull)) \
	         $(sort $(wildcard ../examples/*/*/Docker_Pull.*))
images :=    $(images_ch) $(images_eg)

# Favor embedded Bats, if installed, over system Bats.
export PATH := $(CURDIR)/bats/bin:$(PATH)

# Used by "make all" at top level to build these files for "make install".
.PHONY: all
all: build_auto.bats run_auto.bats \
	 sotest/bin/sotest sotest/lib/libsotest.so.1.0

.PHONY: test
test: test-build test-run
ifneq ($(CH_TEST_SCOPE),quick)
test: test-test
endif

.PHONY: test-build
test-build: build_auto.bats
	bats build.bats build_auto.bats build_post.bats

# Note: This will will not find ch-run correctly if $CWD is not the test
# directory, which I believe is assumed elsewhere in the test suite as well.
.PHONY: test-run
test-run: run_auto.bats
	bats run_first.bats run_auto.bats run/*.bats
	set -e; \
	if [ "$$CH_TEST_SCOPE" != "quick" ]; then \
	    for GUEST_USER in $$(id -un) root nobody; do \
	        for GUEST_GROUP in $$(id -gn) root $$(id -gn nobody); do \
	        export GUEST_USER; \
	        export GUEST_GROUP; \
	        echo testing as: $$GUEST_USER $$GUEST_GROUP; \
	        bats run/ch-run_uidgid.bats; \
	    done; \
	done; fi

# FIXME: This could be sped up by skipping bats if the image is out of scope.
.PHONY: test-test
test-test: $(images_eg)
	set -e; \
	for image in $(images_eg); do \
	export CH_TEST_TAG=$$(./make-auto tag $$image); \
	bats $$(dirname $$image)/test.bats; \
	done

.PHONY: clean
clean:
	rm -f *_auto.bats
	rm -f sotest/sotest sotest/libsotest.so*
	rm -f sotest/bin/sotest sotest/lib/libsotest.so*

.PHONY: where-bats
where-bats:
	which bats
	bats --version

build_auto.bats: $(images)
	./make-auto build $^ > $@

run_auto.bats: $(images)
	./make-auto run $^ > $@

sotest/bin/sotest: sotest/sotest
	cp -a $^ $@
sotest/lib/libsotest.so.1.0: sotest/libsotest.so.1.0
	cp -a $^ $@

# We hardcode gcc here because some other compilers (hello, Intel) link the
# resulting binaries with extra shared libraries that are then not copied into
# the container. (Issue #227.)

sotest/sotest: sotest/sotest.c sotest/libsotest.so.1.0
	gcc -o $@ -L./sotest -lsotest $^
sotest/libsotest.so.1.0: sotest/libsotest.c
	gcc -o $@ -shared -fPIC -Wl,-soname,libsotest.so.1 -lc $^
	ln -f -s libsotest.so.1.0 sotest/libsotest.so
	ln -f -s libsotest.so.1.0 sotest/libsotest.so.1

# PREFIX is the prefix expected at runtime (usually /usr or /usr/local for
#  system-wide installations).
#  More: https://www.gnu.org/prep/standards/html_node/Directory-Variables.html
#
# DESTDIR is the installation directory using during make install, which
#  usually coincides for manual installation, but is chosen to be a temporary
#  directory in packaging environments. PREFIX needs to be appended.
#  More: https://www.gnu.org/prep/standards/html_node/DESTDIR.html
#
# Reasoning here: Users performing manual install *have* to specify PREFIX;
# default is to use that also for DESTDIR. If DESTDIR is provided in addition,
# we use that for installation.
#
# PREFIX can be relative unless DESTDIR is set. Absolute paths are not
# canonicalized.
ifneq ($(PREFIX),)
ifneq ($(shell echo "$(PREFIX)" | cut -c1),/)
  ifdef DESTDIR
    $(error PREFIX must be absolute if DESTDIR is set)
  endif
  override PREFIX := $(abspath $(PREFIX))
  $(warning Relative PREFIX converted to $(PREFIX))
endif
endif
INSTALL_PREFIX := $(if $(DESTDIR),$(DESTDIR)/$(PREFIX),$(PREFIX))
# LIBEXEC_DIR is modeled after FHS 3.0 and
# # https://www.gnu.org/prep/standards/html_node/Directory-Variables.html. It
# # contains any executable helpers that are not needed in PATH. Default is
# # libexec/charliecloud which will be preprended with the PREFIX.
LIBEXEC_DIR	?= libexec/charliecloud
LIBEXEC_INST 	:= $(INSTALL_PREFIX)/$(LIBEXEC_DIR)
LIBEXEC_RUN 	:= $(PREFIX)/$(LIBEXEC_DIR)
EXAMPLES 	:= $(LIBEXEC_INST)/examples
TEST 	:= $(LIBEXEC_INST)/test

.PHONY: install
install: all
	mkdir -p $(EXAMPLES)
	chmod 755 $(EXAMPLES)
	cd ../ && for i in examples/*; do \
	cp -rp $$i $(EXAMPLES); \
	done
	chmod 755 $$(find $(EXAMPLES) -type d)
	chmod 755 $(EXAMPLES)/serial/hello/hello.sh \
	          $(EXAMPLES)/syscalls/pivot_root \
	          $(EXAMPLES)/syscalls/userns \
	          $(EXAMPLES)/*/*/*.sh;
#	tests
	cd ../ && cp -rp test $(TEST)
	chmod 755 $$(find $(TEST) -type d)
	chmod 755 $$(find $(TEST) -name 'Build.*' -or \
	                          -name 'make-auto' -or \
	                          -name 'make-perms-test')
	chmod 644 $$(find $(TEST) -name '*.bats' -or \
	                          -name '*.bash' -or \
	                          -name 'Dockerfile.*' -or \
	                          -name 'Docker_Pull.*' -or \
	                          -name 'Makefile' -or \
	                          -name '*.patch')
	chmod 644 $$(find $(TEST)/chtest -type f)
	chmod 755 $$(find $(TEST)/chtest -name 'Build' -or \
	                                 -name '*.py' -or \
	                                 -name 'printns')
	ln -sf ../../..//bin $(TEST)/bin;
#	shared library tests
	chmod 755 $$(find $(TEST)/sotest -name 'libsotest.so*' -or \
	                                 -name 'sotest')
	chmod 644 $$(find $(TEST)/sotest -name '*.txt' -or \
	                                 -name '*.c')
	cd sotest \
	&& ln -sf ./libsotest.so.1.0 $(TEST)/sotest/libsotest.so \
	&& ln -sf ./libsotest.so.1.0 $(TEST)/sotest/libsotest.so.1
	rm -f $$(find $(TEST) -name GITKEEP)
#	Bats (if embedded);
	if [ -d test/bats/bin ]; then \
	cp -rp bats $(TEST)/bats; \
	chmod 644 $(TEST)/bats $$(find -name '*.md' -or \
	                               -name 'LICENSE'); \
	chmod 755 $$(find $(TEST)/bats -type d); \
	ln -sf ./bats/libexec/bats $(TEST)/bats/bin/bats && \
	ln -sf ./bats/bin/bats $(TEST)/bats; \
	fi
