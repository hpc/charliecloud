SUBDIRS = bin test 
ACLOCAL_AMFLAGS  = -I m4

# VERSION.full contains the version string reported by executables; see FAQ.
# Need s to be converted to an AM_CONDITIONAL 
#ifeq ($(shell test -d .git && fgrep -q \~ VERSION && echo true),true)
#.PHONY: VERSION.full  # depends on git metadata, not a simple file
#VERSION.full: VERSION
#    (git --version > /dev/null 2>&1) || \
#          (echo "This is a Git working directory but no git found." && false)
#    printf '%s+%s%s%s\n' \
#           $$(cat $<) \
#           $$(  git rev-parse --abbrev-ref HEAD \
#              | sed 's/[^A-Za-z0-9]//g' \
#              | sed 's/$$/./g' \
#              | sed 's/master.//g') \
#           $$(git rev-parse --short HEAD) \
#           $$(git diff-index --quiet HEAD || echo '.dirty') \
#           > $@
#else
#VERSION.full: VERSION
#    cp $< $@
#endif
#bin/version.h: VERSION.full
#    echo "#define VERSION \"$$(cat $<)\"" > $@
#bin/version.sh: VERSION.full
#    echo "version () { echo 1>&2 '$$(cat $<)'; }" > $@
