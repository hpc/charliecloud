AC_PREREQ([2.69])
AC_INIT([charliecloud], [0.11], [rustyd@lanl.gov])
AC_CONFIG_SRCDIR([bin/version.h])
AC_CONFIG_HEADERS([config.h])

# Checks for programs.
AC_PROG_CC
# Needed for C11 to work
AC_PROG_CC_STDC
AC_PROG_INSTALL
AC_PROG_LN_S
AC_PROG_MAKE_SET

#AX_PTHREAD(,AC_MSG_ERROR([Missing pthread support]))
#AX_PTHREAD([have_pthread_std=yes],[have_pthread_std=no])
#LIBS="$PTHREAD_LIBS $PTHREAD_CFLAGS $LIBS"
#CFLAGS="$CFLAGS $PTHREAD_CFLAGS"
#CXXFLAGS="$CXXFLAGS $PTHREAD_CFLAGS"

# Checks for libraries.
# FIXME: Replace `main' with a function in `-lc':
AC_CHECK_LIB([c], [main])
# FIXME: Replace `main' with a function in `-lrt':
AC_CHECK_LIB([rt], [clock_gettime])
# FIXME: Replace `main' with a function in `-lsotest':
#AC_CHECK_LIB([sotest], [main])

# Checks for header files.
AC_CHECK_HEADERS([fcntl.h limits.h stdlib.h string.h sys/mount.h sys/statvfs.h unistd.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_CHECK_HEADER_STDBOOL
AC_TYPE_UID_T
AC_TYPE_PID_T
AC_TYPE_SIZE_T

# Checks for library functions.
AC_FUNC_GETGROUPS
AC_HEADER_MAJOR
AC_FUNC_MMAP
AC_FUNC_REALLOC
AC_CHECK_FUNCS([clock_gettime fchdir ftruncate gethostname memset mkdir munmap realpath rmdir setenv strdup strerror strstr strtol])

AC_CONFIG_FILES([Makefile
                 bin/Makefile])

#                 doc-src/Makefile
#                 examples/mpi/mpihello/Makefile
#                 test/Makefile
#                 test/chtest/Makefile])

AC_CONFIG_AUX_DIR([build-aux])

AM_INIT_AUTOMAKE([-Wall -Werror foreign subdir-objects])
AC_OUTPUT
