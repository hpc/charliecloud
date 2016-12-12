export LC_ALL := C
DOCKERFILES := chtest/Dockerfile \
               $(sort $(wildcard ./Dockerfile.*)) \
               $(sort $(wildcard ../examples/*/Dockerfile))
EXAMPLETESTS := $(sort $(wildcard ../examples/*/test.bats))
ifdef CH_TEST_OMIT
  EXAMPLETESTS := $(foreach i,$(EXAMPLETESTS),$(if $(findstring $(CH_TEST_OMIT),$(i)),,$(i)))
endif

.PHONY: test
test: test-build test-run

.PHONY: test-all
test-all: test test-test

.PHONY: test-build
test-build: build_auto.bats
	./bats build.bats build_auto.bats build_post.bats

.PHONY: test-run
test-run: run_auto.bats
	./bats run.bats run_auto.bats
	set -e; \
	for GUEST_USER in $$(id -un) root nobody; do \
	    for GUEST_GROUP in $$(id -gn) root nogroup; do \
	        export GUEST_USER; \
	        export GUEST_GROUP; \
	        echo testing as: $$GUEST_USER $$GUEST_GROUP; \
	        ./bats run_uidgid.bats; \
	    done; \
	done

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
