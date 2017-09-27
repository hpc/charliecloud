export LC_ALL := C
DOCKERS := chtest/Dockerfile \
               $(sort $(wildcard ./Dockerfile.*)) \
               $(sort $(wildcard ../examples/*/*/Dockerfile)) \
               $(sort $(wildcard ../examples/*/*/dockerpull))
DOCKERSQUICK := chtest/Dockerfile
EXAMPLETESTS := $(sort $(wildcard ../examples/*/*/test.bats))
ifdef CH_TEST_OMIT
  EXAMPLETESTS := $(foreach i,$(EXAMPLETESTS),$(if $(findstring $(CH_TEST_OMIT),$(i)),,$(i)))
endif

# Used by "make all" at top level to build these files for "make install".
.PHONY: all
all: build_auto.bats build_auto-quick.bats run_auto.bats

.PHONY: test
test: test-build test-run

.PHONY: test-all
test-all: test test-test

.PHONY: test-build
test-build: build_auto.bats
	./bats build.bats build_auto.bats build_post.bats

# Note: This will will not find ch-run correctly if $CWD is not the test
# directory, which I believe is assumed elsewhere in the test suite as well.
.PHONY: test-run
test-run: run_auto.bats
	./bats run.bats run_uidgid.bats run_auto.bats
	set -e; \
	if ( ! bin/ch-run --is-setuid ); then \
	for GUEST_USER in $$(id -un) root nobody; do \
	    for GUEST_GROUP in $$(id -gn) root $$(id -gn nobody); do \
	        export GUEST_USER; \
	        export GUEST_GROUP; \
	        echo testing as: $$GUEST_USER $$GUEST_GROUP; \
	        ./bats run_uidgid.bats; \
	    done; \
	done; fi

.PHONY: test-test
test-test: $(EXAMPLETESTS)
	./bats $(EXAMPLETESTS)

.PHONY: test-quick
test-quick: build_auto-quick.bats
	./bats build.bats build_auto-quick.bats run.bats

.PHONY: clean
clean:
	rm -f *_auto*.bats

build_auto.bats: $(DOCKERS)
	./make-auto build $^ > $@

build_auto-quick.bats: $(DOCKERSQUICK)
	./make-auto build $^ > $@

run_auto.bats: $(DOCKERS)
	./make-auto run $^ > $@
