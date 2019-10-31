AC_INIT([Charliecloud], [m4_esyscmd_s([misc/version])],
        [https://github.com/hpc/charliecloud])
AC_PREREQ([2.69])
AC_CONFIG_SRCDIR([bin/charliecloud.h])
AC_CONFIG_AUX_DIR([build-aux])

AM_INIT_AUTOMAKE([1.15 -Wall -Werror foreign subdir-objects])

AC_CONFIG_HEADERS([bin/config.h])
AC_CONFIG_FILES([Makefile])

# Need a C11 compiler. (See https://stackoverflow.com/a/28558338.)
AC_PROG_CC
AC_DEFUN([CH_CFLAGS], [-std=c11 -Wall -Werror])
AX_CHECK_COMPILE_FLAG([CH_CFLAGS], [
  CFLAGS+=" CH_CFLAGS"
], [
  echo "no suitable C compiler found"
  exit -1
])

# Libraries.
AC_CHECK_LIB([rt], [clock_gettime])
AX_PTHREAD

AC_OUTPUT
