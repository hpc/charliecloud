# This Makefile started with the default Makefile produced by the Sphinx
# initialization process, which we then modified over time. During the
# Automake-ification, I stripped out most of the boilderplate and left only
# the targets that we use.

EXTRA_DIST = bugs.rst \
	     charliecloud.rst \
	     ch-build2dir_desc.rst \
	     ch-build2dir.rst \
	     ch-build_desc.rst \
	     ch-builder2squash_desc.rst \
	     ch-builder2squash.rst \
	     ch-builder2tar_desc.rst \
	     ch-builder2tar.rst \
	     ch-build.rst \
	     ch-checkns_desc.rst \
	     ch-checkns.rst \
	     ch-dir2squash_desc.rst \
	     ch-dir2squash.rst \
	     ch-fromhost_desc.rst \
	     ch-fromhost.rst \
	     ch-grow_desc.rst \
	     ch-grow.rst \
	     ch-mount_desc.rst \
	     ch-mount.rst \
	     ch-pull2dir_desc.rst \
	     ch-pull2dir.rst \
	     ch-pull2tar_desc.rst \
	     ch-pull2tar.rst \
	     ch-run_desc.rst \
	     ch-run-oci_desc.rst \
	     ch-run-oci.rst \
	     ch-run.rst \
	     ch-ssh_desc.rst \
	     ch-ssh.rst \
	     ch-tar2dir_desc.rst \
	     ch-tar2dir.rst \
	     ch-tar2squash_desc.rst \
	     ch-tar2squash.rst \
	     ch-test_desc.rst \
	     ch-test.rst \
	     ch-umount_desc.rst \
	     ch-umount.rst \
	     command-usage.rst \
	     conf.py \
	     dev.rst \
	     faq.rst \
	     favicon.ico \
	     index.rst \
	     install.rst \
	     logo-sidebar.png \
	     make-deps-overview \
	     rd100-winner.png \
	     see_also.rst \
	     tutorial.rst

man1_MANS = man/charliecloud.1 \
	    man/ch-build.1 \
	    man/ch-build2dir.1 \
	    man/ch-builder2squash.1 \
	    man/ch-builder2tar.1 \
	    man/ch-checkns.1 \
	    man/ch-dir2squash.1 \
	    man/ch-fromhost.1 \
	    man/ch-grow.1 \
	    man/ch-mount.1 \
	    man/ch-pull2dir.1 \
	    man/ch-pull2tar.1 \
	    man/ch-run.1 \
	    man/ch-run-oci.1 \
	    man/ch-ssh.1 \
	    man/ch-tar2dir.1 \
	    man/ch-tar2squash.1 \
	    man/ch-test.1 \
	    man/ch-umount.1

html_DATA = html/searchindex.js \
	    html/_images/rd100-winner.png \
	    html/command-usage.html \
	    html/dev.html \
	    html/faq.html \
	    html/index.html \
	    html/install.html \
	    html/tutorial.html \
	    html/vm.html

# NOTE: ./html might be a Git checkout to support "make web", so make sure not
# to delete it.
CLEANFILES = $(man1_MANS) $(html_DATA) html/.buildinfo html/.nojekyll
# Automake can't remove directories.
clean-local:
	rm -Rf doctrees html/_static


# You can set these variables from the command line.
SPHINXOPTS    = -W
SPHINXBUILD   = @SPHINX@
PAPER         =
BUILDDIR      = .

# Internal variables.
ALLSPHINXOPTS   = -d $(BUILDDIR)/doctrees $(SPHINXOPTS) .

if ENABLE_HTML
all: html
endif
if ENABLE_MAN
all: man
endif

# This target works around a race condition in Sphinx that's triggered when
# two instances (e.g., for html and man targets) try to "mkdir doctrees"
# simultaneously. It is temporary and can be removed when Sphinx >= 1.6.6 is
# an appropriate dependency. See issue #115.
.PHONY: mkdir_issue115
	mkdir -p $(BUILDDIR)/doctrees

$(html_DATA): html
html: mkdir_issue115 ../libexec/version.full
	$(SPHINXBUILD) -b html $(ALLSPHINXOPTS) $(BUILDDIR)/html
# remove unused files that Sphinx made
	rm -R $(BUILDDIR)/html/_sources
	rm $(BUILDDIR)/html/charliecloud.html
	rm $(BUILDDIR)/html/ch-*.html
	rm $(BUILDDIR)/html/bugs.html
	rm $(BUILDDIR)/html/objects.inv
	rm $(BUILDDIR)/html/search.html
	rm $(BUILDDIR)/html/see_also.html

$(man1_MANS): man
man: mkdir_issue115 ../libexec/version.full
	$(SPHINXBUILD) -b man $(ALLSPHINXOPTS) $(BUILDDIR)/man
