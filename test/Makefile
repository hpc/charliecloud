export LC_ALL := C
DOCKERFILES := chtest/Dockerfile \
               $(sort $(wildcard ./Dockerfile.*)) \
               $(sort $(wildcard ../examples/*/Dockerfile))
EXAMPLETESTS := $(sort $(wildcard ../examples/*/test.bats))
ifdef CH_TEST_OMIT
  EXAMPLETESTS := $(foreach i,$(EXAMPLETESTS),$(if $(findstring $(CH_TEST_OMIT),$(i)),,$(i)))
endif

# Used by "make all" at top level to build these files for "make install".
.PHONY: all
all: build_auto.bats run_auto.bats

.PHONY: test
test: test-build test-run

.PHONY: test-all
test-all: test test-test

.PHONY: test-build
test-build: build_auto.bats
	./bats build.bats build_auto.bats build_post.bats

.PHONY: test-run
test-run: run_auto.bats
	./bats run.bats run_uidgid.bats run_auto.bats
	set -e; \
	if ( ! ../bin/ch-run --is-setuid ); then \
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

.PHONY: clean
clean:
	rm -f *_auto.bats

build_auto.bats: $(DOCKERFILES)
	./make-auto build $^ > $@

run_auto.bats: $(DOCKERFILES)
	./make-auto run $^ > $@
