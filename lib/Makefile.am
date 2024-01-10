# Define an alias for pkglibdir to override Automake helpfulness:
#
#   error: 'pkglibdir' is not a legitimate directory for 'DATA'
#
# See: https://www.gnu.org/software/automake/manual/html_node/Uniform.html
mylibdir = $(pkglibdir)

dist_mylib_DATA = base.sh \
                  build.py \
                  build_cache.py \
                  charliecloud.py \
                  filesystem.py \
                  force.py \
                  image.py \
                  misc.py \
                  pull.py \
                  push.py \
                  registry.py
mylib_DATA = contributors.bash \
             version.py \
             version.sh \
             version.txt

# Bundled Lark (currently version 1.1.9); Automake does not support wildcards
# [1], so list the files. Note it's version-specific. Hopefully if a new
# version of Lark adds a file and we omit it here by mistake, the tests will
# catch it. To get this list:
#
# $ (cd lib && find lark lark-*.dist-info -xtype f) | LC_ALL=C sort | sed -E 's/$/ \\/'
#
# Then, copy-n-paste & remove the last backslash. PROOFREAD YOUR DIFF!!!

LARK = \
lark-1.1.9.dist-info/INSTALLER \
lark-1.1.9.dist-info/LICENSE \
lark-1.1.9.dist-info/METADATA \
lark-1.1.9.dist-info/RECORD \
lark-1.1.9.dist-info/WHEEL \
lark-1.1.9.dist-info/entry_points.txt \
lark-1.1.9.dist-info/top_level.txt \
lark/__init__.py \
lark/ast_utils.py \
lark/common.py \
lark/exceptions.py \
lark/grammar.py \
lark/grammars/__init__.py \
lark/grammars/common.lark \
lark/grammars/lark.lark \
lark/grammars/python.lark \
lark/grammars/unicode.lark \
lark/indenter.py \
lark/lark.py \
lark/lexer.py \
lark/load_grammar.py \
lark/parse_tree_builder.py \
lark/parser_frontends.py \
lark/parsers/__init__.py \
lark/parsers/cyk.py \
lark/parsers/earley.py \
lark/parsers/earley_common.py \
lark/parsers/earley_forest.py \
lark/parsers/grammar_analysis.py \
lark/parsers/lalr_analysis.py \
lark/parsers/lalr_interactive_parser.py \
lark/parsers/lalr_parser.py \
lark/parsers/lalr_parser_state.py \
lark/parsers/xearley.py \
lark/py.typed \
lark/reconstruct.py \
lark/tools/__init__.py \
lark/tools/nearley.py \
lark/tools/serialize.py \
lark/tools/standalone.py \
lark/tree.py \
lark/tree_matcher.py \
lark/tree_templates.py \
lark/utils.py \
lark/visitors.py
if ENABLE_LARK
nobase_dist_mylib_DATA = $(LARK)
endif

CLEANFILES = $(mylib_DATA)

contributors.bash: ../README.rst
	rm -f $@
	printf '# shellcheck shell=bash\n' >> $@
	printf 'declare -a ch_contributors\n' >> $@
	sed -En 's/^\*.+<(.+@.+)>.*$$/ch_contributors+=('"'"'\1'"'"')/p' < $< >> $@

# Remove empty charliecloud directories after uninstallation.
uninstall-hook:
	rmdir $$(find $(pkglibdir) -type d | sort -r)

version.txt: ../configure
	printf '@PACKAGE_VERSION@\n' > $@

version.py: ../configure
	printf "VERSION='@PACKAGE_VERSION@'\n" > $@

version.sh: ../configure
	printf "# shellcheck shell=sh disable=SC2034\n" > $@
	printf "ch_version='@PACKAGE_VERSION@'\n" >> $@
