#!/bin/bash

set -e

if [[ $1 = --help ]]; then
    cat <<EOF
Usage:

  $ ./autogen.sh [--clean]

Remove and rebuild Autotools files (./configure and friends). This script is
intended for developers; end users typically do not need it.

Options:

  --clean  remove only; do not rebuild

EOF
    exit 0
fi

cat <<EOF
Removing and (maybe) rebuilding "configure" and friends.

NOTE 1: This script is intended for developers. End users typically do not
        need it.

NOTE 2: Incomprehensible error messages about undefined macros can appear
        below. This is usually caused by missing Autotools components.

See the install instructions for details on both.

EOF

set -x

# Remove existing Autotools stuff, if present. Coordinate with .gitignore.
# We don't run "make clean" because that runs configure again.
rm -rf Makefile \
       Makefile.in \
       ./*/Makefile \
       ./*/Makefile.in \
       aclocal.m4 \
       autom4te.cache \
       bin/.deps \
       bin/config.h \
       bin/config.h.in \
       bin/stamp-h1 \
       build-aux \
       config.log \
       config.status \
       configure

# Create configure and friends.
if [[ $1 != --clean ]]; then
    autoreconf --force --install -Wall -Werror
    if [[ $(command -v  python3) ]]; then
	if [[ $(command -v pip3) ]]; then
	    rm -rf --one-file-system lib/python_modules/lark*
	    pip3 install -t lib/python_modules lark-parser==0.11.2
	fi
    fi
    set +x
    echo
    echo 'Done. Now you can "./configure".'
fi

