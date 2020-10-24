# This Makefile started with the default Makefile produced by the Sphinx
# initialization process, which we then modified over time. During the
# Automake-ification, I stripped out most of the boilderplate and left only
# the targets that we use.

EXTRA_DIST = \
bugs.rst \
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
man/README \
py_env.rst \
rd100-winner.png \
see_also.rst \
tutorial.rst

if ENABLE_MAN
dist_man_MANS = \
man/charliecloud.7 \
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
man/ch-test.1 \
man/ch-umount.1
endif

if ENABLE_HTML
nobase_html_DATA = \
html/searchindex.js \
html/_images/rd100-winner.png \
html/command-usage.html \
html/dev.html \
html/faq.html \
html/index.html \
html/install.html \
html/search.html \
html/tutorial.html
endif


# NOTE: ./html might be a Git checkout to support "make web", so make sure not
# to delete it.
CLEANFILES = $(dist_man_MANS) $(nobase_html_DATA) \
             _deps.rst html/.buildinfo html/.nojekyll
if ENABLE_HTML
# Automake can't remove directories.
clean-local:
	rm -Rf doctrees html/_sources html/_static html/_images
endif

# Automake can't install and uninstall directories. _static contains around
# one hundred files in several directories, and I'm pretty sure the contents
# change depending on Sphinx version and other details, so we can't just list
# the files. These targets deal with it as an opaque directory. The _sources
# directory is another generated directory that contains references to the
# input .rst files which we need for searching to work so we give it a similar
# treatment.
if ENABLE_HTML
install-data-hook:
	cp -r html/_sources $(DESTDIR)$(htmldir)/html
	cp -r html/_static $(DESTDIR)$(htmldir)/html
	find $(DESTDIR)$(htmldir)/html/_sources -xtype f -exec chmod 644 {} \;
	find $(DESTDIR)$(htmldir)/html/_static -xtype d -exec chmod 755 {} \;
	find $(DESTDIR)$(htmldir)/html/_static -xtype f -exec chmod 644 {} \;

uninstall-hook:
	   test -d $(DESTDIR)$(htmldir)/html/_sources \
	&& rm -Rf $(DESTDIR)$(htmldir)/html/_sources \;
	   test -d $(DESTDIR)$(htmldir)/html/_static \
	&& rm -Rf $(DESTDIR)$(htmldir)/html/_static \;
	   test -d $(DESTDIR)$(htmldir)/html/_images \
	&& rm -Rf $(DESTDIR)$(htmldir)/html/_images \;
endif

# You can set these variables from the command line.
SPHINXOPTS    = -W
SPHINXBUILD   = @SPHINX@
PAPER         =
BUILDDIR      = .

# Internal variables.
ALLSPHINXOPTS   = -d $(BUILDDIR)/doctrees $(SPHINXOPTS) .

# This target works around a race condition in Sphinx that's triggered when
# two instances (e.g., for html and man targets) try to "mkdir doctrees"
# simultaneously. It is temporary and can be removed when Sphinx >= 1.6.6 is
# an appropriate dependency. See issue #115.
.PHONY: mkdir_issue115
	mkdir -p $(BUILDDIR)/doctrees

_deps.rst: ../config.log make-deps-overview
	cat $< | ./make-deps-overview > $@

# This called "html-local" because Automake has a Texinfo target called "html"
# and gripes if we override it.
$(nobase_html_DATA): html-local
html-local: mkdir_issue115 ../lib/version.txt _deps.rst
	$(SPHINXBUILD) -b html $(ALLSPHINXOPTS) $(BUILDDIR)/html
# avoid GitHub messing things up with Jekyll
	touch html/.nojekyll
# remove unused files that Sphinx made
	rm -f $(BUILDDIR)/html/_deps.html \
	      $(BUILDDIR)/html/charliecloud.html \
	      $(BUILDDIR)/html/ch-*.html \
	      $(BUILDDIR)/html/bugs.html \
	      $(BUILDDIR)/html/objects.inv \
	      $(BUILDDIR)/html/see_also.html

# FIXME: If Sphinx builds the man pages first, the HTML docs don't get curly
# quotes. ¯\_(ツ)_/¯ Force HTML to go first.
if ENABLE_HTML
HTML_FIRST = html
endif

$(dist_man_MANS): man
man: mkdir_issue115 ../lib/version.txt _deps.rst $(HTML_FIRST)
	$(SPHINXBUILD) -b man $(ALLSPHINXOPTS) $(BUILDDIR)/man
