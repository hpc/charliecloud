AC_INIT([Charliecloud], [m4_esyscmd_s([misc/version])],
        [https://github.com/hpc/charliecloud])
AC_PREREQ([2.69])
AC_CONFIG_SRCDIR([bin/ch-run.c])
AC_CONFIG_AUX_DIR([build-aux])

AM_INIT_AUTOMAKE([1.15 -Wall -Werror foreign subdir-objects])

AC_CONFIG_HEADERS([bin/config.h])
AC_CONFIG_FILES([Makefile bin/Makefile])

# Need a C11 compiler. (See https://stackoverflow.com/a/28558338.)
AC_PROG_CC
AC_DEFUN([CH_CFLAGS], [-std=c11 -Wall -Werror])
AX_CHECK_COMPILE_FLAG([CH_CFLAGS], [
  CFLAGS+=" CH_CFLAGS"
], [
  AC_MSG_ERROR([no C11 compiler found])
])
AS_IF([test "$CC" = icc],
      [AC_MSG_ERROR([icc not supported (see PR 481)])])

## Libraries

# Need pthreads for ch-run --join.
AX_PTHREAD

# Docs recommend AC_SEARCH_LIBS, but I couldn't get it to not put "-lrt" in
# LIBS. We only need it for ch-run.
AC_CHECK_LIB([rt], [shm_open], [LIBRT=-lrt], [
  AC_MSG_ERROR([shm_open(3) not found])
])
AC_SUBST([LIBRT])


## Options


## Feature tests

# Sphinx. FIXME: For now, we are not validating the underlying Python and
# docutils versions.
# - exists and executable
# - minimum version
vmin_sphinx=1.4.9
with_sphinx=$SPHINX
AX_WITH_PROG([SPHINX], [sphinx-build])
AS_IF([test "x$SPHINX" != x], [
  AC_MSG_CHECKING([if sphinx-build is executable])
  AS_IF([test -e "$SPHINX"],
        [AC_MSG_RESULT([ok])],
        [AC_MSG_RESULT([no])
         AC_MSG_ERROR([not executable: $SPHINX])])
  AC_MSG_CHECKING([sphinx-build version at least $vmin_sphinx])
  vact_sphinx=$("$SPHINX" --version | sed -E 's/sphinx-build //')
  AX_COMPARE_VERSION([$vmin_sphinx], [le], [$vact_sphinx],
    [AC_MSG_RESULT([ok ($vact_sphinx)])],
    [AC_MSG_RESULT([too old ($vact_sphinx)])
     AS_UNSET(SPHINX)
     AS_UNSET(vact_sphinx)])
])

# User namespaces
AC_MSG_CHECKING([if user+mount namespaces work])
AC_RUN_IFELSE([AC_LANG_SOURCE([[
    #define _GNU_SOURCE
    #include <sched.h>

    int main(void)
    {
       if (unshare(CLONE_NEWNS|CLONE_NEWUSER))
          return 1;  // syscall failed
       else
          return 0;  // syscall succeeded
    }
  ]])],
  [have_userns=yes
   AC_DEFINE(HAVE_USERNS, 1, [user+mount namespaces work])],
  [have_userns=no],
  [AC_MSG_ERROR([cross-compilation not supported])])
AC_MSG_RESULT($have_userns)


## Print report

AC_MSG_NOTICE([

  configure options:

  build-time dependencies:

    C11 compiler           ${CC} ${CC_VERSION}
    sphinx-build $vmin_sphinx+    ${SPHINX:-not found} ${vact_sphinx}

  run-time dependencies (informational only):

    user+mount namespaces  ${have_userns}

])


## Done

AC_OUTPUT
