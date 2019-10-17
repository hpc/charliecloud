#!/bin/sh -x
libtoolize
aclocal
autoheader
autoreconf --install
rm -f install-sh
ln -s build-aux/install-sh .
