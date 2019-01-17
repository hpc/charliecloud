SHELL=/bin/bash

# Add some good stuff to CFLAGS.
export CFLAGS += -std=c11 -Wall

.PHONY: all
all: VERSION.full bin/version.h bin/version.sh
	cd bin && $(MAKE) all
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
# * Otherwise, we add the Git branch if the current branch is not master, the 
#   Git commit, and a note if the working directory
#   contains uncommitted changes, e.g. "0.2.3~pre+experimental.ae24a4e.dirty".
ifeq ($(shell test -d .git && fgrep -q \~ VERSION && echo true),true)
.PHONY: VERSION.full  # depends on git metadata, not a simple file
VERSION.full: VERSION
	(git --version > /dev/null 2>&1) || \
          (echo "This is a Git working directory but no git found." && false)
	printf '%s+%s%s%s\n' \
	       $$(cat $<) \
	       $$(git rev-parse --abbrev-ref HEAD | sed 's/.*/&./g' | sed 's/master.//g') \
	       $$(git rev-parse --short HEAD) \
	       $$(git diff-index --quiet HEAD || echo '.dirty') \
	       > $@
else
VERSION.full: VERSION
	cp $< $@
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
	    sed -i "s#^libexec=.*#libexec=$(LIBEXEC_RUN)#" $(BIN)/$${scriptfile}; \
	done
#       executable helpers
	install -d $(LIBEXEC_INST)
	install -pm 644 -t $(LIBEXEC_INST) bin/base.sh bin/version.sh
	sed -i "s#^libexec=.*#libexec=$(LIBEXEC_RUN)#" $(LIBEXEC_INST)/base.sh
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
	          $(DOC)/examples/syscalls/userns \
	          $(DOC)/examples/*/*/*.sh
	find $(DOC)/examples -name Build -exec chmod 755 {} \;
#       tests
	install -d $(TEST) $(TEST)/run
	install -pm 644 -t $(TEST) test/*.bats test/common.bash test/Makefile
	install -pm 644 -t $(TEST)/run test/run/*.bats
	install -pm 755 -t $(TEST) test/Build.*
	install -pm 644 -t $(TEST) test/Dockerfile.* test/Docker_Pull.*
	install -pm 755 -t $(TEST) test/make-auto test/make-perms-test
	install -d $(TEST)/chtest
	install -pm 644 -t $(TEST)/chtest test/chtest/*
	chmod 755 $(TEST)/chtest/{Build,*.py,printns}
	ln -sf ../../../../bin $(TEST)/bin
#       shared library tests
	install -d $(TEST)/sotest $(TEST)/sotest/bin $(TEST)/sotest/lib
	install -pm 755 -t $(TEST)/sotest test/sotest/libsotest.so.1.0 \
	                                  test/sotest/sotest 
	install -pm 644 -t $(TEST)/sotest test/sotest/files_inferrable.txt \
	                                  test/sotest/sotest.c
	ln -sf ./libsotest.so.1.0 $(TEST)/sotest/libsotest.so
	ln -sf ./libsotest.so.1.0 $(TEST)/sotest/libsotest.so.1
	install -pm 755 -t $(TEST)/sotest/bin test/sotest/bin/sotest
	install -pm 755 -t $(TEST)/sotest/lib test/sotest/lib/libsotest.so.1.0
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

.PHONY: deb
deb:
	ln -s packaging/debian
	debuild -d -i -us -uc
	rm -f debian
