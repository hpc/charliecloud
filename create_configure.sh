libtoolize --force
aclocal
autoheader
automake --force-missing --add-missing
ln -s build-aux/install-sh .
autoconf
# Hacky workaround
./configure
