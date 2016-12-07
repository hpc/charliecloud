export LC_ALL := C
DOCKERFILES := $(sort $(wildcard ./Dockerfile.*)) \
               $(sort $(wildcard ../examples/*/Dockerfile))
EXAMPLETESTS := $(sort $(wildcard ../examples/*/test.bats))

.PHONY: test-all test-all-quick test-build permdirs test-run-quick clean

test: test-build test-run

test-all: test test-test

test-quick: test-build-quick test-run-quick

test-build-quick: build.bats
	./bats build.bats

test-build: test-build-quick build_auto.bats
	./bats build_auto.bats

test-run-quick: run.bats run_uidgid.bats
	./bats run.bats
	set -e; \
	for GUEST_USER in $$(id -un) root nobody; do \
	    for GUEST_GROUP in $$(id -gn) root nogroup; do \
	        export GUEST_USER; \
	        export GUEST_GROUP; \
	        echo testing as: $$GUEST_USER $$GUEST_GROUP; \
	        ./bats run_uidgid.bats; \
	    done; \
	done

test-run: test-run-quick run_auto.bats
	./bats run_auto.bats

test-test:
	./bats $(EXAMPLETESTS)

clean:
	rm -f *_auto.bats

build_auto.bats: $(DOCKERFILES)
	./make-auto build $^ > $@

run_auto.bats: $(DOCKERFILES)
	./make-auto run $^ > $@
