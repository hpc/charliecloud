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
	cd doc-src && $(MAKE) clean
	cd test && $(MAKE) clean
	cd examples/syscalls && $(MAKE) clean

# VERSION.full contains the version string reported by the executables.
#
# * If VERSION is an unadorned release (e.g. 0.2.3 not 0.2.3~pre), or there's
#   no Git information available, VERSION.full is simply a copy of VERSION.
#
# * Otherwise, we add the Git commit and a note if the working directory
#   contains uncommitted changes, e.g. "0.2.3~pre+ae24a4e.dirty".
#
ifeq ($(shell test -d .git && fgrep -q \~ VERSION && echo true),true)
.PHONY: VERSION.full  # depends on git metadata, not a simple file
VERSION.full:
	printf '%s+%s%s\n' \
	       $$(cat VERSION) \
	       $$(git rev-parse --short HEAD) \
	       $$(git diff-index --quiet HEAD || echo '.dirty') \
	       > VERSION.full
else
VERSION.full: VERSION
	cp VERSION VERSION.full
endif
bin/version.h: VERSION.full
	echo "#define VERSION \"$$(cat $<)\"" > $@
bin/version.sh: VERSION.full
	echo "version () { echo 1>&2 '$$(cat $<)'; }" > $@

# Yes, this is bonkers. We keep it around even though normal "git archive" or
# the zip files on Github work, because it provides an easy way to create a
# self-contained tarball with embedded Bats and man pages.
#
# You must "cd doc-src && make" before this will work.
.PHONY: export
export: VERSION.full man/charliecloud.1
	test -d .git -a -f test/bats/.git  # need recursive Git checkout
#	git diff-index --quiet HEAD        # need clean working directory
	git archive HEAD --prefix=charliecloud-$$(cat VERSION.full)/ \
                         -o main.tar
	cd test/bats && \
          git archive HEAD \
            --prefix=charliecloud-$$(cat ../../VERSION.full)/test/bats/ \
            -o ../../bats.tar
	tar Af main.tar bats.tar
	tar --xform=s,^,charliecloud-$$(cat VERSION.full)/, \
            -rf main.tar \
            man/*.1 VERSION.full
	gzip -9 main.tar
	mv main.tar.gz charliecloud-$$(cat VERSION.full).tar.gz
	rm bats.tar
	ls -lh charliecloud-$$(cat VERSION.full).tar.gz

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
INSTALL_PREFIX := $(if $(DESTDIR),$(DESTDIR)/$(PREFIX),$(PREFIX))
BIN := $(INSTALL_PREFIX)/bin
DOC := $(INSTALL_PREFIX)/share/doc/charliecloud
TEST := $(DOC)/test
# LIBEXEC_DIR is modeled after FHS 3.0 and
# https://www.gnu.org/prep/standards/html_node/Directory-Variables.html. It
# contains any executable helpers that are not needed in PATH. Default is
# libexec/charliecloud which will be preprended with the PREFIX.
LIBEXEC_DIR ?= libexec/charliecloud
LIBEXEC_INST := $(INSTALL_PREFIX)/$(LIBEXEC_DIR)
LIBEXEC_RUN := $(PREFIX)/$(LIBEXEC_DIR)
.PHONY: install
install: all
	@test -n "$(PREFIX)" || \
          (echo "No PREFIX specified. Lasciando ogni speranza." && false)
	@echo Installing in $(INSTALL_PREFIX)
#       binaries
	install -d $(BIN)
	install -pm 755 -t $(BIN) $$(find bin -type f -executable)
#       Modify scripts to relate to new libexec location.
	for scriptfile in $$(find bin -type f -executable -printf "%f\n"); do \
	    sed -i "s#^LIBEXEC=.*#LIBEXEC=$(LIBEXEC_RUN)#" $(BIN)/$${scriptfile}; \
	done
#       Install ch-run setuid if either SETUID=yes is specified or the binary
#       in the build directory is setuid.
	if [ -n "$(SETUID)" ]; then \
            if [ $$(id -u) -eq 0 ]; then \
	        chown root $(BIN)/ch-run; \
	        chmod u+s $(BIN)/ch-run; \
	    else \
	        sudo chown root $(BIN)/ch-run; \
	        sudo chmod u+s $(BIN)/ch-run; \
	    fi \
	elif [ -u bin/ch-run ]; then \
	    sudo chmod u+s $(BIN)/ch-run; \
	fi
#       executable helpers
	install -d $(LIBEXEC_INST)
	install -pm 644 -t $(LIBEXEC_INST) bin/base.sh bin/version.sh
	sed -i "s#^LIBEXEC=.*#LIBEXEC=$(LIBEXEC_RUN)#" $(LIBEXEC_INST)/base.sh
#       man pages if they were built
	if [ -f man/charliecloud.1 ]; then \
	    install -d $(INSTALL_PREFIX)/share/man/man1; \
	    install -pm 644 -t $(INSTALL_PREFIX)/share/man/man1 man/*.1; \
	fi
#       misc "documentation"
	install -d $(DOC)
	install -pm 644 -t $(DOC) LICENSE README.rst
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
	ln -sf ../../../../bin $(TEST)/bin
#       Bats (if embedded)
	if [ -d test/bats/bin ]; then \
	    install -d $(TEST)/bats && \
	    install -pm 644 -t $(TEST)/bats test/bats/CONDUCT.md \
	                                    test/bats/LICENSE \
	                                    test/bats/README.md && \
	    install -d $(TEST)/bats/libexec && \
	    install -pm 755 -t $(TEST)/bats/libexec test/bats/libexec/* && \
	    install -d $(TEST)/bats/bin && \
	    ln -sf ../libexec/bats $(TEST)/bats/bin/bats && \
	    ln -sf bats/bin/bats $(TEST)/bats; \
	fi
