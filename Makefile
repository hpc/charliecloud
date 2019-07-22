SHELL=/bin/sh
PYTHON=$(shell command -v "$$(head -1 test/make-auto | sed -E 's/^.+ //')")

# Add some good stuff to CFLAGS.
export CFLAGS += -std=c11 -Wall -g

.PHONY: all
all: VERSION.full bin/version.h bin/version.sh
	cd bin && $(MAKE) all
#       only descend into test/ if the right Python is available
	[ -z $(PYTHON) ] || cd test && $(MAKE) all

.PHONY: clean
clean:
	cd bin && $(MAKE) clean
	cd doc-src && $(MAKE) clean
	cd test && $(MAKE) clean

# VERSION.full contains the version string reported by executables; see FAQ.
ifeq ($(shell test -d .git && fgrep -q \~ VERSION && echo true),true)
.PHONY: VERSION.full  # depends on git metadata, not a simple file
VERSION.full: VERSION
	(git --version > /dev/null 2>&1) || \
          (echo "This is a Git working directory but no git found." && false)
	printf '%s+%s%s%s\n' \
	       $$(cat $<) \
	       $$(  git rev-parse --abbrev-ref HEAD \
	          | sed 's/[^A-Za-z0-9]//g' \
	          | sed 's/$$/./g' \
	          | sed 's/master.//g') \
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

# These targets provide tarballs of HEAD (not the Git working directory) that
# are self-contained, including the source code as well as the man pages
# (both) and Bats (export-bats). To use them in an unclean working directory,
# set $CH_UNCLEAN_EXPORT_OK to non-empty.
#
# You must "cd doc-src && make" before they will work. The targets depend on
# the man pages but don't know how to build them.
#
# They are phony because I haven't figured out their real dependencies.
.PHONY: main.tar
main.tar: VERSION.full man/charliecloud.1 doc/index.html
	git diff-index --quiet HEAD || [ -n "$$CH_MAKE_EXPORT_UNCLEAN_OK" ]
	git archive HEAD --prefix=charliecloud-$$(cat VERSION.full)/ \
                         -o main.tar
	tar --xform=s,^,charliecloud-$$(cat VERSION.full)/, \
	    --exclude='.*' \
	    -rf main.tar doc man/*.1 VERSION.full

.PHONY: export
export: main.tar
	gzip -9 main.tar
	mv main.tar.gz charliecloud-$$(cat VERSION.full).tar.gz
	ls -lh charliecloud-$$(cat VERSION.full).tar.gz

.PHONY: export-bats
export-bats: main.tar
	test -d .git -a -f test/bats/.git  # need recursive Git checkout
	cd test/bats && \
          git archive HEAD \
            --prefix=charliecloud-$$(cat ../../VERSION.full)/test/bats/ \
            -o ../../bats.tar
	tar Af main.tar bats.tar
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
VERSION := $(shell cat VERSION.full)
INSTALL_PREFIX := $(if $(DESTDIR),$(DESTDIR)/$(PREFIX),$(PREFIX))
BIN := $(INSTALL_PREFIX)/bin
DOCDIR ?= $(INSTALL_PREFIX)/share/doc/charliecloud-$(VERSION)
# LIBEXEC_DIR is modeled after FHS 3.0 and
# https://www.gnu.org/prep/standards/html_node/Directory-Variables.html. It
# contains any executable helpers that are not needed in PATH. Default is
# libexec/charliecloud which will be preprended with the PREFIX.
LIBEXEC_DIR ?= libexec/charliecloud-$(VERSION)
export LIBEXEC_INST := $(INSTALL_PREFIX)/$(LIBEXEC_DIR)
LIBEXEC_RUN  := $(PREFIX)/$(LIBEXEC_DIR)
export TEST  := $(LIBEXEC_INST)/test
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
#       license and readme
	install -d $(DOCDIR)
	install -pm 644 -t $(DOCDIR) LICENSE README.rst
#	html files if they were built
	if [ -f doc/index.html ]; then \
	    cp -r doc $(DOCDIR)/html; \
	    rm -f $(DOCDIR)/html/.nojekyll; \
	    for i in $$(find $(DOCDIR)/html -type d); do \
	        chmod 755 $$i; \
	    done; \
	    for i in $$(find $(DOCDIR)/html -type f); do \
	        chmod 644 $$i; \
	    done; \
	fi
#	install test suite and examples if the right python is found
	[ -z $(PYTHON) ] || $(MAKE) install $(PREFIX) -C test

.PHONY: deb
deb:
	ln -s packaging/debian
	debuild -d -i -us -uc
	rm -f debian
