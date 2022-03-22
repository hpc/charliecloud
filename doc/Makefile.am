# This Makefile started with the default Makefile produced by the Sphinx
# initialization process, which we then modified over time. During the
# Automake-ification, I stripped out most of the boilderplate and left only
# the targets that we use.

# We turn off parallel build in doc:
#
#   1. Sphinx handles building the whole documentation internally already, as
#      a unit, so we shouldn't call sphinx-build more than once for different
#      output files at all, let alone in parallel.
#
#   2. Serial build is plenty fast.
#
#   3. There is a race condition in Sphinx < 1.6.6 that's triggered when two
#      instances (e.g., for html and man targets) try to "mkdir doctrees"
#      simultaneously. See issue #115.
#
# This special target was introduced in GNU Make 3.79, in April 2000.
.NOTPARALLEL:

EXTRA_DIST = \
bugs.rst \
charliecloud.rst \
ch-checkns_desc.rst \
ch-checkns.rst \
ch-convert_desc.rst \
ch-convert.rst \
ch-fromhost_desc.rst \
ch-fromhost.rst \
ch-image_desc.rst \
ch-image.rst \
ch-run_desc.rst \
ch-run-oci_desc.rst \
ch-run-oci.rst \
ch-run.rst \
ch-ssh_desc.rst \
ch-ssh.rst \
ch-test_desc.rst \
ch-test.rst \
command-usage.rst \
conf.py \
dev.rst \
faq.rst \
favicon.ico \
index.rst \
install.rst \
loc.rst \
logo-sidebar.png \
make-deps-overview \
man/README \
py_env.rst \
rd100-winner.png \
see_also.rst \
tutorial.rst

if ENABLE_MAN
man_MANS = \
man/charliecloud.7 \
man/ch-checkns.1 \
man/ch-convert.1 \
man/ch-fromhost.1 \
man/ch-image.1 \
man/ch-run.1 \
man/ch-run-oci.1 \
man/ch-ssh.1 \
man/ch-test.1
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
CLEANFILES = $(man_MANS) $(nobase_html_DATA) \
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

_deps.rst: ../config.log make-deps-overview
	cat $< | ./make-deps-overview > $@

# Since we're not doing anything in parallel anyway, just put the HTML and the
# man pages in the same target, with conditionals. Gotchas:
#
#   1. If we build both, the HTML needs to go first otherwise it doesn't get
#      curly quotes. ¯\_(ツ)_/¯
#
#   2. This not a "grouped target" but rather an "independent target" [1],
#      because the former came in GNU Make 4.3 which is quite new. However it
#      does seem to get run only once.
#
# [1]: https://www.gnu.org/software/make/manual/html_node/Multiple-Targets.html
$(nobase_html_DATA) $(man_MANS): ../lib/version.txt ../README.rst _deps.rst $(EXTRA_DIST)
if ENABLE_HTML
	$(SPHINXBUILD) -b html $(ALLSPHINXOPTS) $(BUILDDIR)/html
#       Avoid GitHub messing things up with Jekyll.
	touch html/.nojekyll
#       Some output files are copies with same timestamp as source; fix. Note
#       we need all the HTML output files, not just the one picked in $@.
	touch --no-create $(nobase_html_DATA)
#       remove unused files that Sphinx made
	rm -f $(BUILDDIR)/html/_deps.html \
	      $(BUILDDIR)/html/charliecloud.html \
	      $(BUILDDIR)/html/ch-*.html \
	      $(BUILDDIR)/html/bugs.html \
	      $(BUILDDIR)/html/loc.html \
	      $(BUILDDIR)/html/objects.inv \
	      $(BUILDDIR)/html/see_also.html
endif
if ENABLE_MAN
	$(SPHINXBUILD) -b man $(ALLSPHINXOPTS) $(BUILDDIR)/man
endif
