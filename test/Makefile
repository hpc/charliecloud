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
images := $(images_ch) $(images_eg)
sotests := sotest/bin/sotest sotest/lib/libsotest.so.1.0

# Favor embedded Bats, if installed, over system Bats.
export PATH := $(CURDIR)/bats/bin:$(PATH)

# Used by "make all" at top level to build these files for "make install".
.PHONY: all
all: build_auto.bats run_auto.bats $(sotests)

.PHONY: test
test: test-build test-run
ifneq ($(CH_TEST_SCOPE),quick)
test: test-test
endif

.PHONY: test-build
test-build: build_auto.bats $(sotests)
	bats build.bats build_auto.bats build_post.bats

# Note: This will will not find ch-run correctly if $CWD is not the test
# directory, which I believe is assumed elsewhere in the test suite as well.
.PHONY: test-run
test-run: run_auto.bats $(sotests)
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
	    done; \
	fi

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

build_auto.bats: $(images) make-auto
	./make-auto build $^ > $@

run_auto.bats: $(images) make-auto
	./make-auto run $^ > $@

sotest/bin/sotest: sotest/sotest
	cp -a $^ $@
sotest/lib/libsotest.so.1.0: sotest/libsotest.so.1.0
	cp -a $^ $@

# We hardcode gcc here because some other compilers (hello, Intel) link the
# resulting binaries with extra shared libraries that are then not copied into
# the container. (Issue #227.)

sotest/sotest: sotest/sotest.c sotest/libsotest.so.1.0
	gcc -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -L./sotest -lsotest $^
sotest/libsotest.so.1.0: sotest/libsotest.c
	gcc -o $@ $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) -shared -fPIC -Wl,-soname,libsotest.so.1 -lc $^
	ln -f -s libsotest.so.1.0 sotest/libsotest.so
	ln -f -s libsotest.so.1.0 sotest/libsotest.so.1

.PHONY: install
install: all
	cd ../ && \
	for i in examples/serial/* examples/mpi/* examples/other/*; do \
		install -d $(LIBEXEC_INST)/$$i; \
		install -pm 644 -t $(LIBEXEC_INST)/$$i $$i/*; \
	done
	chmod 755 $(LIBEXEC_INST)/examples/serial/hello/hello.sh \
	          $(LIBEXEC_INST)/examples/*/*/*.sh
	find $(LIBEXEC_INST)/examples -name Build -exec chmod 755 {} \;
#	tests
	install -d $(TEST) $(TEST)/run
	install -pm 644 -t $(TEST) *.bats common.bash Makefile
	install -pm 644 -t $(TEST)/run run/*.bats
	install -pm 755 -t $(TEST) Build.*
	install -pm 644 -t $(TEST) Dockerfile.* Docker_Pull.*
	install -pm 644 -t $(TEST) *.patch
	install -pm 755 -t $(TEST) docs-sane \
                               make-auto \
                               make-perms-test
	install -d $(TEST)/chtest
	install -pm 644 -t $(TEST)/chtest chtest/*
	chmod 755 $(TEST)/chtest/Build \
	          $(TEST)/chtest/*.py \
	          $(TEST)/chtest/printns
	ln -sf ../../../bin $(TEST)/bin
#	shared library tests
	install -d $(TEST)/sotest $(TEST)/sotest/bin $(TEST)/sotest/lib
	install -pm 755 -t $(TEST)/sotest sotest/libsotest.so.1.0 \
	                                  sotest/sotest
	install -pm 644 -t $(TEST)/sotest sotest/files_inferrable.txt \
	                                  sotest/libsotest.c \
	                                  sotest/sotest.c
	ln -sf ./libsotest.so.1.0 $(TEST)/sotest/libsotest.so
	ln -sf ./libsotest.so.1.0 $(TEST)/sotest/libsotest.so.1
	install -pm 755 -t $(TEST)/sotest/bin sotest/bin/sotest
	install -pm 755 -t $(TEST)/sotest/lib sotest/lib/libsotest.so.1.0
#	Bats (if embedded)
	if [ -d test/bats/bin ]; then \
	    install -d $(TEST)/bats && \
	    install -pm 644 -t $(TEST)/bats bats/CONDUCT.md \
	                                    bats/LICENSE \
	                                    bats/README.md && \
	    install -d $(TEST)/bats/libexec && \
	    install -pm 755 -t $(TEST)/bats/libexec bats/libexec/* && \
	    install -d $(TEST)/bats/bin && \
	    ln -sf ../libexec/bats $(TEST)/bats/bin/bats && \
	    ln -sf bats/bin/bats $(TEST)/bats; \
	fi
