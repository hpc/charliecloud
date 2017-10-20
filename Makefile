SHELL=/bin/bash

# Add some good stuff to CFLAGS.
export CFLAGS += -std=c11 -Wall

.PHONY: all
all: VERSION.full bin/version.h bin/version.sh
	cd bin && $(MAKE) SETUID=$(SETUID) all
	cd test && $(MAKE) all
	cd examples/syscalls && $(MAKE) all

.PHONY: clean
clean:
	cd bin && $(MAKE) clean
	cd test && $(MAKE) clean
	cd examples/syscalls && $(MAKE) clean

# If we're in a Git checkout, rebuild VERSION.full every time (since it's hard
# to tell if it needs to be rebuilt). If not, it had better be there since we
# can't build it.
ifeq ($(wildcard .git),.git)
.PHONY: VERSION.full
VERSION.full:
	printf '%s+%s%s\n' \
	       $$(cat VERSION) \
               $$(git rev-parse --short HEAD) \
	       $$(git diff-index --quiet HEAD || echo '.dirty') \
	       > VERSION.full
endif
bin/version.h: VERSION.full
	echo "#define VERSION \"$$(cat $<)\"" > $@
bin/version.sh: VERSION.full
	echo "version () { echo 1>&2 '$$(cat $<)'; }" > $@

# Yes, this is bonkers.
.PHONY: export
export: VERSION.full
	git diff-index --quiet HEAD  # only export if WD is clean
	git archive HEAD --prefix=charliecloud-$$(cat VERSION.full)/ \
                         -o main.tar
	cd test/bats.src && \
          git archive HEAD \
            --prefix=charliecloud-$$(cat ../../VERSION.full)/test/bats.src/ \
            -o ../../bats.tar
	tar Af main.tar bats.tar
	tar --xform=s,^,charliecloud-$$(cat VERSION.full)/, \
            -rf main.tar \
            VERSION.full
	gzip -9 main.tar
	mv main.tar.gz charliecloud-$$(cat VERSION.full).tar.gz
	rm bats.tar
	ls -lh charliecloud-$$(cat VERSION.full).tar.gz

BIN=$(PREFIX)/bin
DOC=$(PREFIX)/share/doc/charliecloud
TEST=$(DOC)/test
.PHONY: install
install: all
	@test -n "$(PREFIX)" || \
          (echo "No PREFIX specified. Lasciando ogni speranza." && false)
	@echo Installing in $(PREFIX)
#       binaries
	install -d $(BIN)
	install -pm 755 -t $(BIN) $$(find bin -type f -executable)
	if [ -u bin/ch-run ]; then sudo chmod u+s $(BIN)/ch-run; fi
	install -pm 644 -t $(BIN) bin/base.sh bin/version.h bin/version.sh
#       misc "documentation"
	install -d $(DOC)
	install -pm 644 -t $(DOC) COPYRIGHT LICENSE README.rst
#       examples
	for i in examples/syscalls examples/{serial,mpi,other}/*; do \
	    install -d $(DOC)/$$i; \
	    install -pm 644 -t $(DOC)/$$i $$i/*; \
	done
	chmod 755 $(DOC)/examples/serial/hello/hello.sh \
	          $(DOC)/examples/syscalls/pivot_root \
	          $(DOC)/examples/syscalls/userns
	find $(DOC)/examples -name Build -exec chmod 755 {} \;
#       tests
	install -d $(TEST)
	install -pm 644 -t $(TEST) test/*.bats test/common.bash test/Makefile
	install -pm 755 -t $(TEST) test/Build.*
	install -pm 644 -t $(TEST) test/Dockerfile.* test/Docker_Pull.*
	install -pm 755 -t $(TEST) test/make-perms-test
	install -d $(TEST)/chtest
	install -pm 644 -t $(TEST)/chtest test/chtest/*
	chmod 755 $(TEST)/chtest/Build $(TEST)/chtest/*.py
	install -d $(TEST)/bats.src
	install -pm 644 -t $(TEST)/bats.src \
	        test/bats.src/CONDUCT.md test/bats.src/LICENSE \
                test/bats.src/README.md
	install -d $(TEST)/bats.src/libexec
	install -pm 755 -t $(TEST)/bats.src/libexec \
	        test/bats.src/libexec/*
	install -d $(TEST)/bats.src/bin
	ln -sf ../libexec/bats $(TEST)/bats.src/bin/bats
	ln -sf bats.src/bin/bats $(TEST)/bats
	ln -sf ../../../../bin $(TEST)/bin
