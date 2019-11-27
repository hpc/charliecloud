# TODO
#
#   - clean up and finalize documentation
#   - finish ./configure runtime status report
#   - script libexec lines: remove quotes
#   - ch-test: fix libexec lines
#   - ch-test: pass
#   - conver Python scripts to version.py
#   - build docs, with correct sphinx-build
#   - document Autotools Archive dependency
#   - make sure executable sanity check doesn't depend solely on wildcards
#   - use shell variable for CH_CFLAGS?
#   - sotest shared library
#   - figure out "make web"
#   - make the --disable options work
#   - --disable-ch-grow: make sure tests work
#   - ch-run: need ch_core.h in sources

# Gotchas:
#
# 1. Quadrigraphs. M4 consumes a number of important special characters, so
#    Autoconf uses 4-character sequences, e.g. "@%:@" is the octothorpe (#).
#    See: https://www.gnu.org/software/autoconf/manual/autoconf-2.69/html_node/Quadrigraphs.html
#
# 2. Booleans. The convention for Autoconf variables, which we follow, is
#    "yes" for true and "no" for false. This differs from the Charliecloud
#    convention of non-empty for true and empty for false.

AC_INIT([Charliecloud], [m4_esyscmd_s([misc/version])],
        [https://github.com/hpc/charliecloud])
AC_PREREQ([2.69])
AC_CONFIG_SRCDIR([bin/ch-run.c])
AC_CONFIG_AUX_DIR([build-aux])

AM_INIT_AUTOMAKE([1.15 -Wall -Werror foreign subdir-objects])

AC_CONFIG_HEADERS([bin/config.h])
AC_CONFIG_FILES([Makefile bin/Makefile libexec/Makefile misc/Makefile])

# Need a C11 compiler. (See https://stackoverflow.com/a/28558338.)
AC_PROG_CC
AC_DEFUN([CH_CFLAGS], [-std=c11 -Wall -Werror])
AX_CHECK_COMPILE_FLAG([CH_CFLAGS], [
  CFLAGS+=" CH_CFLAGS"
], [
  AC_MSG_ERROR([no C11 compiler found])
])
AS_IF([test "$CC" = icc],
      [AC_MSG_ERROR([icc not supported (see PR @%:@481)])])

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

# Note: --with-sphinx-build provided by AX_WITH_PROG() below.

AC_ARG_WITH([python-shebang],
  AS_HELP_STRING(
    [--with-python-shebang=@<:@SHEBANG@:>@],
    [Python shebang to use for scripts (default: "/usr/bin/env python3")]),
  [PYTHON_SHEBANG="$withval"],
  [PYTHON_SHEBANG='/usr/bin/env python3'])
AC_MSG_CHECKING([if "$PYTHON_SHEBANG" starts with slash])
AS_CASE([$PYTHON_SHEBANG],
  [/*], [AC_MSG_RESULT([ok])],
  [*],  [AC_MSG_RESULT([no])
         AC_MSG_ERROR([--with-python-shebang: must start with slash])])
AC_SUBST([PYTHON_SHEBANG])

AC_ARG_ENABLE([html],
  AS_HELP_STRING([--disable-html], [don't build and install HTML docs]),
  [], [enable_html=yes])

AC_ARG_ENABLE([man],
  AS_HELP_STRING([--disable-man], [don't build and install man pages]),
  [], [enable_man=yes])

AC_ARG_ENABLE([test],
  AS_HELP_STRING([--disable-test], [don't build and install test suite]),
  [], [enable_test=yes])

AC_ARG_ENABLE([ch-grow],
  AS_HELP_STRING([--disable-ch-grow],
                 [don't build and install ch-grow unprivileged builder]),
  [], [enable_ch_grow=yes])


## Feature test macros

# Macro to validate executable versions. Arguments:
#
#   $1  name of variable containing executable name or absolute path
#   $2  minimum version
#   $3  append to $1 to make shell pipeline to get actual version only
#       (e.g., without program name)
#
# If ${!1} is empty, do nothing.
#
# If minimum version is less than actual version, unset $1. Otherwise, also
# set $1_VERSION to the actual version.
#
# If given absolute path, and that file isn't executable, error out.
AC_DEFUN([CH_CHECK_VERSION], [
  AS_VAR_PUSHDEF([prog], [$1])
  AS_IF([test -n "$prog"], [
    AS_CASE([$prog],
      [/*], [AC_MSG_CHECKING([if $prog is executable])
             AS_IF([test -e "$prog"],
              [AC_MSG_RESULT([ok])],
              [AC_MSG_RESULT([no])
               AC_MSG_ERROR([must be executable])])])
    AC_MSG_CHECKING([if $prog version >= $2])
    vact=$($prog $3)
    AX_COMPARE_VERSION([$2], [le], [$vact],
      [AC_MSG_RESULT([ok ($vact)])
       AC_SUBST([$1_VERSION], [$vact])],
      [AC_MSG_RESULT([too old ($vact)])
       AS_UNSET([$1])])
  ])
  AS_VAR_POPDEF([prog])
])


## Feature tests - build time

vmin_sphinx=1.4.9
AX_WITH_PROG([SPHINX], [sphinx-build])
CH_CHECK_VERSION([SPHINX], [$vmin_sphinx],
                 [--version | sed -E 's/sphinx-build //'])


## Feature tests - run time

vmin_bash=4.1
AC_CHECK_PROG([_BASH], [bash], [bash])  # $BASH and $BASH_VERSION already used
CH_CHECK_VERSION([_BASH], [$vmin_bash], [--version | head -1 | cut -d' ' -f4])

# docker
# mktemp
# buildah

vmin_python=3.4
python="${PYTHON_SHEBANG#/usr/bin/env }"                # use shell to find it
AS_CASE([$python],
  [/*], [PYTHON="$python"],                              # absolute
  [*],  [AC_CHECK_PROG([PYTHON], [$python], [$python])]  # verify it's in $PATH
)
CH_CHECK_VERSION([PYTHON], [$vmin_python], [--version | cut -d' ' -f2])

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


## Adjust build options given what we have available

AS_IF([test "$enable_html" = yes && test -z "$SPHINX"],
      [AC_MSG_WARN([forcing --disable-html: no suitable sphinx-build])
       enable_html=no])

AS_IF([test "$enable_man" = yes && test -z "$SPHINX"],
      [AC_MSG_WARN([forcing --disable-man: no suitable sphinx-build])
       enable_man=no])


## Done

AC_OUTPUT


## Print report

AC_MSG_NOTICE([

  build-time:

    C11 compiler           ${CC} ${CC_VERSION}
    sphinx-build $vmin_sphinx+    ${SPHINX:-not found} ${SPHINX_VERSION}

    build and install:
      HTML documentation   ${enable_html}
      man pages            ${enable_man}
      test suite           ${enable_test}
      ch-grow builder      ${enable_ch_grow}

  run-time (informational only):

    Bash $vmin_bash+               ${_BASH_VERSION:-not found}
    Python shebang line     ${PYTHON_SHEBANG}
    Python in shebang $vmin_python+  ${PYTHON_VERSION:-no or not found}
    user+mount namespaces   ${have_userns}
])
