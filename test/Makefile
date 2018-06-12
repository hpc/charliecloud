export LC_ALL := C
IMAGES :=      chtest/Build \
               $(sort $(wildcard ./Build.*)) \
               $(sort $(wildcard ./Dockerfile.*)) \
               $(sort $(wildcard ./Docker_Pull.*)) \
               $(sort $(wildcard ../examples/*/*/Build)) \
               $(sort $(wildcard ../examples/*/*/Dockerfile)) \
               $(sort $(wildcard ../examples/*/*/Docker_Pull))
EXAMPLETESTS := $(sort $(wildcard ../examples/*/*/test.bats))

# Favor embedded Bats, if installed, over system Bats.
export PATH := $(CURDIR)/bats/bin:$(PATH)

# Used by "make all" at top level to build these files for "make install".
.PHONY: all
all: build_auto.bats run_auto.bats \
     sotest/bin/sotest sotest/lib/libsotest.so.1.0

.PHONY: test
test: test-build test-run test-test

.PHONY: test-build
test-build: build_auto.bats
	bats build.bats build_auto.bats build_post.bats

# Note: This will will not find ch-run correctly if $CWD is not the test
# directory, which I believe is assumed elsewhere in the test suite as well.
.PHONY: test-run
test-run: run_auto.bats
	bats run.bats run_uidgid.bats run_auto.bats run_join.bats run_post.bats
	set -e; \
        if [ "$$CH_TEST_SCOPE" != "quick" ]; then \
	for GUEST_USER in $$(id -un) root nobody; do \
	    for GUEST_GROUP in $$(id -gn) root $$(id -gn nobody); do \
	        export GUEST_USER; \
	        export GUEST_GROUP; \
	        echo testing as: $$GUEST_USER $$GUEST_GROUP; \
	        bats run_uidgid.bats; \
	    done; \
	done; fi

.PHONY: test-test
test-test: $(EXAMPLETESTS)
	bats $(EXAMPLETESTS)

.PHONY: clean
clean:
	rm -f *_auto.bats
	rm -f sotest/sotest sotest/libsotest.so*
	rm -f sotest/bin/sotest sotest/lib/libsotest.so*

.PHONY: where-bats
where-bats:
	which bats
	bats --version

build_auto.bats: $(IMAGES)
	./make-auto build $^ > $@

run_auto.bats: $(IMAGES)
	./make-auto run $^ > $@

sotest/bin/sotest: sotest/sotest
	cp -a $^ $@
sotest/lib/libsotest.so.1.0: sotest/libsotest.so.1.0
	cp -a $^ $@

sotest/sotest: sotest/sotest.c sotest/libsotest.so.1.0
	$(CC) -o $@ -L./sotest -lsotest $^
sotest/libsotest.so.1.0: sotest/libsotest.c
	$(CC) -o $@ -shared -fPIC -Wl,-soname,libsotest.so.1 -lc $^
	ln -f -s libsotest.so.1.0 sotest/libsotest.so
	ln -f -s libsotest.so.1.0 sotest/libsotest.so.1
