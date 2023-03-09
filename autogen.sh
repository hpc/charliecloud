#!/bin/bash

set -e
lark_version=0.11.3

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --clean)
            clean=yes
            ;;
        --no-lark)
            lark_no_install=yes
            ;;
        --rm-lark)
            lark_shovel=yes
            ;;
        *)
            help=yes
            ;;
    esac
    shift
done

if [[ $help ]]; then
    cat <<EOF
Usage:

  $ ./autogen.sh [OPTIONS]

Remove and rebuild Autotools files (./configure and friends). This script is
intended for developers; end users typically do not need it.

Options:

  --clean    remove only; do not rebuild
  --help     print this help and exit
  --no-lark  don't install bundled Lark (minimal support; see docs)
  --rm-lark  delete Lark (and then reinstall if not --clean or --no-lark)

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

cd "$(dirname "$0")"
set -x

# Remove all derived files if we can. Note that if you enabled maintainer mode
# in configure, this will run configure before cleaning.
[[ -f Makefile ]] && make maintainer-clean
# “maintainer-clean” target doesn't remove configure and its dependencies,
# apparently by design [1], so delete those manually.
#
# [1]: https://www.gnu.org/prep/standards/html_node/Standard-Targets.html
rm -Rf Makefile.in \
       ./*/Makefile.in \
       aclocal.m4 \
       bin/config.h.in \
       build-aux \
       configure
# Remove Lark, but only if requested.
if [[ $lark_shovel ]]; then
    rm -Rfv lib/lark lib/lark-stubs lib/lark*.dist-info lib/lark*.egg-info
fi

# Create configure and friends.
if [[ -z $clean ]]; then
    autoreconf --force --install -Wall -Werror
    if [[ ! -e lib/lark && ! $lark_no_install ]]; then
        # Install Lark only if its directory doesn’t exist, to avoid excess
        # re-downloads.
        pip3 --isolated install \
             --target=lib --ignore-installed "lark==${lark_version}"
        # Lark doesn’t honor --no-compile, so remove the .pyc files manually.
        rm lib/lark/__pycache__/*.pyc
        rmdir lib/lark/__pycache__
        rm lib/lark/*/__pycache__/*.pyc
        rmdir lib/lark/*/__pycache__
        # Also remove Lark’s installer stuff.
        rm lib/lark/__pyinstaller/*.py
        rmdir lib/lark/__pyinstaller
    fi
    if [[    -e lib/lark \
          && ! -e lib/lark-${lark_version}.dist-info/INSTALLER ]]; then
        set +x
        echo 'error: Embedded Lark is broken.' 2>&1
        echo 'hint: Install "wheel" and then re-run with "--rm-lark"?' 2>&1
        exit 1
    fi
    set +x
    echo
    echo 'Done. Now you can "./configure".'
fi

