# Gotchas:
#
# 1. Quadrigraphs. M4 consumes a number of important special characters, so
#    Autoconf uses 4-character sequences, e.g. "@%:@" is the octothorpe (#).
#    See: https://www.gnu.org/software/autoconf/manual/autoconf-2.69/html_node/Quadrigraphs.html
#
# 2. Booleans. The convention for Autoconf variables, which we follow, is
#    "yes" for true and "no" for false. This differs from the Charliecloud
#    convention of non-empty for true and empty for false.


### Prologue #################################################################

AC_INIT([Charliecloud], [m4_esyscmd_s([misc/version])],
        [https://github.com/hpc/charliecloud])
AC_PREREQ([2.69])
AC_CONFIG_SRCDIR([bin/ch-run.c])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_MACRO_DIRS([misc/m4])

AC_CANONICAL_BUILD
AC_CANONICAL_HOST
AC_CANONICAL_TARGET
AS_CASE([$host_os],
  [linux*], [],
  [*],      [AC_MSG_ERROR([Linux is the only supported OS; see issue @%:@42.])]
)

# Turn off maintainer mode by default. This appears to be controversial; see
# issue #595 for links to some discussion.
#
# Bottom line for me: Maintainer mode has (1) never re-built the build system
# in a situation where I felt it helped, but (2) fairly regularly re-builds or
# re-configures at surprising times.
#
# In particular, it often rebuilds before "make clean" and friends, e.g. if
# you change branches and then clean. This seems wrong. In my view, clean
# should remove what is currently there, not what *would have been there* had
# the build used a different, not-yet-existing build system. Disabling
# maintainer mode also lets us put "make maintainer-clean" in autogen.sh
# without triggering spurious rebuilds.
AM_MAINTAINER_MODE([disable])

# By default, Autotools honors umask for directories but not files. Thus, if
# you "sudo make install" with a umask more restrictive than 0022, the result
# is an installation unavailable to most users (issue #947). This appears to
# be a somewhat common complaint.
#
# Our workaround is to set the "mkdir -p" command [1]. (Note those
# instructions also mention a different variable ac_cv_path_mkdir, but I
# couldn't figure out how to set it.) This needs to be before AM_INIT_AUTOMAKE
# because that macro does something with the value. We use "install -d" rather
# than "mkdir -m" because the latter still uses only umask for intermediate
# directories [2].
#
# This can still be overridden on the configure command line; for example, to
# restore the previous behavior, use "./configure MKDIR_P='mkdir -p'" [3].
#
# [1]: https://unix.stackexchange.com/a/436000
# [2]: http://gnu-automake.7480.n7.nabble.com/bug-12130-sudo-make-install-applies-umask-to-new-directories-tp18545p18548.html
# [3]: https://lists.gnu.org/archive/html/automake/2004-01/msg00013.html
MKDIR_P=${MKDIR_P:-install -d -m 0755}

AM_INIT_AUTOMAKE([1.13 -Wall -Werror foreign subdir-objects])

AC_CONFIG_HEADERS([bin/config.h])
AC_CONFIG_FILES([Makefile
                 bin/Makefile
                 doc/Makefile
                 examples/Makefile
                 lib/Makefile
                 misc/Makefile
                 packaging/Makefile
                 test/Makefile])


### Options ##################################################################

# Note: Variables must match option, e.g. --disable-foo-bar => enable_foo_bar.
# Note: --with-sphinx-build provided by AX_WITH_PROG() below.

AC_ARG_ENABLE([buggy-build],
  AS_HELP_STRING(
    [--enable-buggy-build],
    [omit -Werror; please see docs before use!]),
  [AS_CASE([$enableval],
    [yes], [use_werror=no],
    [no],  [use_werror=yes],
    [*],   [AC_MSG_ERROR([--enable-buggy-build: bad argument: $enableval])]
  )],
  [use_werror=yes])

AC_ARG_ENABLE([bundled-lark],
  AS_HELP_STRING([--disable-bundled-lark],
                 [use system Lark (not recommended; see docs!)]),
  [], [enable_bundled_lark=yes])

AC_ARG_ENABLE([ch-image],
  AS_HELP_STRING([--disable-ch-image],
                 [ch-image unprivileged builder & image manager]),
  [], [enable_ch_image=yes])

AC_ARG_ENABLE([html],
  AS_HELP_STRING([--disable-html], [HTML documentation]),
  [], [enable_html=yes])

AC_ARG_ENABLE([man],
  AS_HELP_STRING([--disable-man], [man pages]),
  [], [enable_man=yes])

AC_ARG_ENABLE([syslog],
  AS_HELP_STRING([--disable-syslog], [logging to syslog]),
  [], [enable_syslog=yes])

AC_ARG_ENABLE([test],
  AS_HELP_STRING([--disable-test], [test suite]),
  [], [enable_test=yes])

AC_ARG_WITH([libsquashfuse],
  AS_HELP_STRING([--with-libsquashfuse=foo], [foo]))
AS_CASE([$with_libsquashfuse],
  [yes], # explicit “yes”
    [want_libsquashfuse=yes
     need_libsquashfuse=yes],
  [no],  # explicit “no”
    [want_libsquashfuse=no
     need_libsquashfuse=no],
  [''],  # option not specified
    [want_libsquashfuse=yes
     need_libsquashfuse=no],
  [*],   # explicit path to libsquashfuse install
    [want_libsquashfuse=yes
     need_libsquashfuse=yes
     lib_libsquashfuse=$with_libsquashfuse/lib
     inc_libsquashfuse=$with_libsquashfuse/include])

AC_ARG_WITH([python],
  AS_HELP_STRING(
    [--with-python=SHEBANG],
    [Python shebang to use for scripts (default: "/usr/bin/env python3")]),
  [PYTHON_SHEBANG="$withval"],
  [PYTHON_SHEBANG='/usr/bin/env python3'])

# Can't deduce shebang from Gentoo "sphinx-python"; allow override. See #629.
AC_ARG_WITH([sphinx-python],
  AS_HELP_STRING(
    [--with-sphinx-python=SHEBANG],
    [Python shebang used by Sphinx (default: deduced from sphinx-build executable]]),
    [sphinx_python="$withval"],
    [sphinx_python=''])


### Feature test macros ######################################################

# Macro to validate executable versions. Arguments:
#
#   $1  name of variable containing executable name or absolute path
#   $2  minimum version
#   $3  append to $1 to make shell pipeline to get actual version only
#       (e.g., without program name)
#
# This macro is not able to determine if a program exists, only whether its
# version is sufficient. ${!1} (i.e, the value of the variable whose name is
# stored in $1) must be either empty, an absolute path to an executable, or
# the name of a program in $PATH. A prior macro such as AX_WITH_PROG can be
# used to ensure this condition.
#
# If ${!1} is an absolute path, and that file isn't executable, error out. If
# it's something other than an absolute path, assume it's the name of a
# program in $PATH; if not, the behavior is undefined but not good (FIXME).
#
# Post-conditions:
#
#   1. If ${!1} is non-empty and the version reported by the program is
#      greater than or equal to the minimum, ${!1} is unchanged. If ${!1} is
#      empty or reported version is insufficient, ${!1} is the empty string.
#      This lets you test version sufficiency by whether ${!1} is empty.
#
#   2. $1_VERSION_NOTE contains a brief explanatory note.
#
AC_DEFUN([CH_CHECK_VERSION], [
  AS_VAR_PUSHDEF([prog], [$1])
  AS_IF([test -n "$prog"], [
    # ${!1} is non-empty
    AS_CASE([$prog],
      # absolute path; check if executable
      [/*], [AC_MSG_CHECKING([if $prog is executable])
             AS_IF([test -e "$prog"],
              [AC_MSG_RESULT([ok])],
              [AC_MSG_RESULT([no])
               AC_MSG_ERROR([must be executable])])])
    AC_MSG_CHECKING([if $prog version >= $2])
    vact=$($prog $3)
    AX_COMPARE_VERSION([$2], [le], [$vact], [
      AC_SUBST([$1_VERSION_NOTE], ["ok ($vact)"])
      AC_MSG_RESULT([ok ($vact)])
    ], [
      AC_SUBST([$1_VERSION_NOTE], ["too old ($vact)"])
      AC_MSG_RESULT([too old ($vact)])
      AS_UNSET([$1])
    ])
  ], [
    # ${!} is empty
    AC_SUBST([$1_VERSION_NOTE], ["not found"])
    AS_UNSET([$1])
  ])
  AS_VAR_POPDEF([prog])
])


### C compiler ###############################################################

# Need a C99 compiler. (See https://stackoverflow.com/a/28558338.)
AC_PROG_CC

# Set up CFLAGS.
ch_cflags='-std=c99 -Wall'
AS_IF([test -n "$lib_libsquashfuse"],
      [ch_cflags+=" -I$inc_libsquashfuse -L$lib_libsquashfuse"
       # Without this, clang fails with "error: argument unused during
       # compilation" on the -L. GCC ignores it.
       ch_cflags+=' -Wno-unused-command-line-argument'])
AS_IF([test $use_werror = yes],
      [ch_cflags+=' -Werror'])

AX_CHECK_COMPILE_FLAG([$ch_cflags], [
  CFLAGS+=" $ch_cflags"
], [
  AC_MSG_ERROR([no suitable C99 compiler found])
])
AS_IF([test "$CC" = icc],
      [AC_MSG_ERROR([icc not supported (see PR @%:@481)])])


### ch-run required ##########################################################

# Only ch-run needs any kind of interesting library stuff; this variable holds
# the library arguments we need. This also requires us to use AC_CHECK_LIB
# instead of the (recommended by docs) AC_SEARCH_LIBS, because that adds
# things to LIBS, which we don't want because it's applied to all executables.
CH_RUN_LIBS=

# asprintf(3)
#
# You can do this with AC_CHECK_FUNC or AC_CHECK_FUNCS, but those macros call
# the function with no arguments. This causes a warning for asprintf() for
# some compilers (and I have no clue why others accept it); see issue #798.
# Instead, try to build a small test program that calls asprintf() correctly.
AC_MSG_CHECKING([for asprintf in libc])
AC_COMPILE_IFELSE([AC_LANG_SOURCE([[
    #define _GNU_SOURCE
    #include <stdio.h>
    #include <stdlib.h>

    int main(void)
    {
       char *p;
       if (asprintf(&p, "WEIRD AL YANKOVIC\n") >= 0)
          free(p);
       return 0;
    }
  ]])],
  [AC_MSG_RESULT([yes])],
  [AC_MSG_RESULT([no])
   AC_MSG_ERROR([asprintf(3) not found; please report this bug])])

# argp_parse(3), which is included with glibc but not other libc’s, e.g. musl.
AC_MSG_CHECKING([for argp_parse in libc])
AC_LINK_IFELSE([AC_LANG_SOURCE([[
    #include <argp.h>

    int main(void)
    {
        argp_parse(0, 1, NULL, 0, 0, 0);
        return 0;
    }
  ]])],
  [AC_MSG_RESULT([yes])],  # built-in, no further action
  [AC_MSG_RESULT([no])     # try external libargp
   AC_CHECK_LIB(
     [argp], [argp_parse],
     [CH_RUN_LIBS="-largp $CH_RUN_LIBS"],
     [AC_MSG_ERROR([argp_parse(3) not found; please report this bug])])])

# pthreads; needed for "ch-run --join".
AX_PTHREAD

# POSIX IPC lives in librt.
AC_CHECK_LIB([rt], [shm_open], [CH_RUN_LIBS="-lrt $CH_RUN_LIBS"], [
  AC_MSG_ERROR([shm_open(3) not found])
])

# User namespaces
AC_MSG_CHECKING([if in chroot])  # https://unix.stackexchange.com/a/14346
AS_IF([test    "$(awk '$5=="/" {print $1}' </proc/1/mountinfo)" \
            != "$(awk '$5=="/" {print $1}' </proc/$$/mountinfo)" ],
      [chrooted=yes],
      [chrooted=no])
AC_MSG_RESULT($chrooted)
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
  [have_userns=yes],
  [have_userns=no],
  [AC_MSG_ERROR([cross-compilation not supported])])
AC_MSG_RESULT($have_userns)


### SquashFS #################################################################

# SquashFS Tools
vmin_mksquashfs=4.2  # CentOS 7
AC_CHECK_PROG([MKSQUASHFS], [mksquashfs], [mksquashfs])
CH_CHECK_VERSION([MKSQUASHFS], [$vmin_mksquashfs],
                 [-version | head -1 | cut -d' ' -f3])

# SquashFUSE executables
vmin_squashfuse=0.1.100  # Ubuntu 16.04 (Xenial). CentOS 7 has 0.1.102.
AC_CHECK_PROG([SQUASHFUSE], [squashfuse], [squashfuse])
CH_CHECK_VERSION([SQUASHFUSE], [$vmin_squashfuse],
                 [--help 2>&1 | head -1 | cut -d' ' -f2])

# libfuse3
AC_CHECK_LIB([fuse3], [fuse_set_signal_handlers],
  [have_libfuse3=yes],
  [have_libfuse3=no])

# libsquashfuse
AC_CHECK_LIB([squashfuse_ll], [sqfs_ll_mount],
  [have_libsquashfuse_ll=yes],
  [have_libsquashfuse_ll=no])
AC_CHECK_HEADER([squashfuse/ll.h],
  [have_ll_h=yes],
  [have_ll_h=no],
  [#define SQFS_CONFIG_H
   #define FUSE_USE_VERSION 32
  ])  # see comment in ch_fuse.c regarding these defines

# Should we link with libsquashfuse?
AS_IF([   test $want_libsquashfuse = yes \
       && test $have_libfuse3 = yes \
       && test $have_libsquashfuse_ll = yes \
       && test $have_ll_h = yes],
      [have_libsquashfuse=yes
       CH_RUN_LIBS="-lsquashfuse_ll -lfuse3 -Wl,-rpath=$lib_libsquashfuse $CH_RUN_LIBS"],
      [have_libsquashfuse=no])
AS_IF([   test $need_libsquashfuse = yes \
       && test $have_libsquashfuse = no],
      [AC_MSG_ERROR([libsquashfuse requested but not found])])

# Any SquashFUSE support at all?
AS_IF([   test -n "$SQUASHFUSE" \
       || test $have_libsquashfuse = yes],
      [have_any_squashfuse=yes],
      [have_any_squashfuse=no])


### ch-image #################################################################

# Python
vmin_python=3.6  # NOTE: Keep in sync with lib/charliecloud.py
AC_MSG_CHECKING([if "$PYTHON_SHEBANG" starts with slash])
AS_CASE([$PYTHON_SHEBANG],
  [/*], [AC_MSG_RESULT([ok])],
  [*],  [AC_MSG_RESULT([no])
         AC_MSG_ERROR([--with-python: must start with slash])])
python="${PYTHON_SHEBANG#/usr/bin/env }"                # use shell to find it
AS_CASE([$python],
  [/*], [PYTHON="$python"],                              # absolute
  [*],  [AC_CHECK_PROG([PYTHON], [$python], [$python])]  # verify it's in $PATH
)
CH_CHECK_VERSION([PYTHON], [$vmin_python],
                 [--version | head -1 | cut -d' ' -f2])

# Python module "requests"
vmin_requests=2.6.0  # CentOS 7; FIXME: haven't actually tested this
AS_IF([test -n "$PYTHON"], [
  AC_MSG_CHECKING([for requests module])
  cat <<EOF | $PYTHON_SHEBANG
import sys
try:
   import requests
except Exception:
   sys.exit(1)
EOF
  AS_IF([test $? -eq 0],
    [REQUESTS=$PYTHON; have_requests=yes],
    [REQUESTS=;         have_requests=no])
  AC_MSG_RESULT($have_requests)
  CH_CHECK_VERSION([REQUESTS], [$vmin_requests],
    [-c 'import requests; print(requests.__version__)'])
])

# Check for bundled Lark; we do not verify or report version. Note this
# assumes that $PWD is the top of the source tree. I don't believe anything
# else is supported (see issue #820), but it's brittle.
AC_MSG_CHECKING([for bundled Lark module])
AS_IF([test -e ./lib/lark-*.dist-info],
      [lark_status=bundled],
      [lark_status=external])
AC_MSG_RESULT($lark_status)
AS_IF([   test $enable_bundled_lark = yes \
       && test $lark_status != bundled],
       [AC_MSG_ERROR([bundled Lark not found; see docs])])


### Docs #####################################################################

# Sphinx
vmin_sphinx=1.2.3
AX_WITH_PROG([SPHINX], [sphinx-build])
CH_CHECK_VERSION([SPHINX], [$vmin_sphinx],
                 [--version | sed -E 's/sphinx-build //'])

# Get the Sphinx Python. We don't care about version.
AS_IF([test -n "$SPHINX"], [
  AS_IF([test -z "$sphinx_python"], [
    AC_MSG_CHECKING([for sphinx-build Python])
    sphinx_python=$(head -1 "$SPHINX" | sed -E -e 's/^#!\s*//' -e 's/\s.*$//')
    AC_MSG_RESULT([$sphinx_python])
  AC_MSG_CHECKING([if "$sphinx_python" starts with slash])
  AS_CASE([$sphinx_python],
    [/*], [AC_MSG_RESULT([ok])],
    [*],  [AC_MSG_RESULT([no])
           AC_MSG_ERROR([--with-sphinx-python: must start with slash])])
])])

# "docutils" module
vmin_docutils=0.14
AS_IF([test -n "$SPHINX"], [
  # Sphinx depends on docutils, so we don't need to check if the module exists
  # before checking its version. (CH_CHECK_VERSION isn't smart enough to deal
  # with Python being present but a module not.)
  DOCUTILS=$sphinx_python  # FIXME: output is confusing
  CH_CHECK_VERSION([DOCUTILS], [$vmin_docutils],
                   [-c 'import docutils; print(docutils.__version__)'])
], [DOCUTILS_VERSION_NOTE='moot b/c no sphinx-build'])

# "sphinx-rtd-theme" module
vmin_rtd=0.2.4
AS_IF([test -n "$SPHINX"], [
  AC_MSG_CHECKING([for sphinx_rtd_theme module])
  cat <<EOF | $sphinx_python
import sys
try:
   import sphinx_rtd_theme
except ImportError:
   sys.exit(1)
EOF
  AS_IF([test $? -eq 0],
    [RTD=$sphinx_python; have_rtd=yes],
    [RTD=;               have_rtd=no])
  AC_MSG_RESULT([$have_rtd])
  CH_CHECK_VERSION([RTD], [$vmin_rtd],
    [-c 'import sphinx_rtd_theme; print(sphinx_rtd_theme.__version__)'])
], [RTD_VERSION_NOTE='moot b/c no sphinx-build'])

# What should we build?
AS_IF([   test -n "$SPHINX" \
       && test -n "$DOCUTILS" \
       && test -n "$RTD" \
       && (test "$enable_man" = yes || test "$enable_html" = yes)],
       [have_docs=yes],
       [have_docs=no])
AS_IF([   test $enable_html = yes && test $have_docs = no],
      [AC_MSG_WARN([forcing --disable-html: no suitable sphinx-build])
       enable_html=no])
AS_IF([   test $enable_man = yes && test $have_docs = no],
      [AC_MSG_WARN([forcing --disable-man: no suitable sphinx-build])
       enable_man=no])


### Glue scripts #############################################################

# Buildah
vmin_buildah=1.11.2
AC_CHECK_PROG([BUILDAH], [buildah], [buildah])
CH_CHECK_VERSION([BUILDAH], [$vmin_buildah], [--version | cut -d' ' -f3])

# Docker
vmin_docker=17.03
AC_CHECK_PROG([DOCKER], [docker], [docker])
CH_CHECK_VERSION([DOCKER], [$vmin_docker], [-v | tr -d , | cut -d' ' -f3])

# mktemp - no version
AC_CHECK_PROG([MKTEMP], [mktemp], [mktemp])

# libnvidia-container-cli
vmin_nvidia_cli=1.0.0
AC_CHECK_PROG([NVIDIA_CLI], [nvidia-container-cli], [nvidia-container-cli])
CH_CHECK_VERSION([NVIDIA_CLI], [$vmin_nvidia_CLI],
                 [-V | head -1 | cut -d' ' -f2])
AC_MSG_CHECKING([for nVidia libraries & executables])
AS_IF([test -n "$NVIDIA_CLI"],
  [AS_IF([nvidia-container-cli list | grep -Fq libnvidia],
        [have_nvidia_libs=yes],
        [have_nvidia_libs=no])],
  [have_nvidia_libs=no])
AC_MSG_RESULT($have_nvidia_libs)


### Test suite ###############################################################

# Bash
vmin_bash=4.1
AC_CHECK_PROG([_BASH], [bash], [bash])  # $BASH and $BASH_VERSION already used
CH_CHECK_VERSION([_BASH], [$vmin_bash], [--version | head -1 | cut -d' ' -f4])

# Bats
vmin_bats=0.4.0
AC_CHECK_PROG([BATS], [bats], [bats])
CH_CHECK_VERSION([BATS], [$vmin_bats], [--version | cut -d' ' -f2])

# ShellCheck
vmin_shellcheck=0.6.0
AC_CHECK_PROG([SHELLCHECK], [shellcheck], [shellcheck])
# https://stackoverflow.com/questions/6022384
CH_CHECK_VERSION([SHELLCHECK], [$vmin_shellcheck],
                 [--version | sed -n '2{s/^version: //;p;q}'])

# sudo, generic
# Avoids prompting for password; see https://superuser.com/a/1183480.
# But logrotate sends an e-mail with every call, so disabled.
#AC_MSG_CHECKING([for generic sudo])
#sudo_out=$(sudo -nv 2>&1)
#AS_IF([   test -z "$sudo_out" \
#       || echo "$sudo_out" | grep -Fq asswor],
#      [have_sudo=yes],
#      [have_sudo=no])
#AC_MSG_RESULT($have_sudo)

# Wget
vmin_wget=1.11  # 2008
AC_CHECK_PROG([WGET], [wget], [wget])
CH_CHECK_VERSION([WGET], [$vmin_wget], [--version | head -1 | cut -d' ' -f3])


### Output variables #########################################################

# Autotools output variables are ... interesting. This is my best
# understanding:
#
#   1. AC_SUBST(foo) does two things in Makefile.am:
#
#      a. Replace the string "@foo@" with the value of foo anywhere it
#         appears.
#
#      b. Set the Make variable foo to the same value, i.e., add "foo = @foo@"
#         which is then substituted as in item 1.
#
#      So this is how you transfer a variable from configure to Make.
#
#   2. AC_SUBST_NOTMAKE(foo) does only (a).
#
#   3. AM_CONDITIONAL(foo, test) creates a variable for use in Automake
#      conditionals. E.g. if you say in configure.ac:
#
#        AM_CONDITIONAL([foo], [test $foo = yes])
#
#      and then in Makefile.am:
#
#        if foo
#            ... bar ...
#        else
#            ... baz ...
#        endif
#
#      then if the configure variable $foo is "yes", lines "... bar ..." will
#      be placed in the Makefile; otherwise, "... baz ..." will be included.
#
#      This is how you include and exclude portions of the Makefile.am from
#      the output Makefile. It *does not* create a Make variable.
#
#   4. AC_DEFINE(foo, value, comment) #define's the preprocessor symbol foo to
#      value in config.h. (Supposedly value and comment are optional but I got
#      warnings doing that.) So this is how you make configure values
#      available in C code (as macros, not variables). Typically you would
#      define something or not (allowing #ifdef), rather than always define to
#      true or false (which would require #if).
#
#   5. AC_DEFINE_UNQUOTES adds some extra transformations to the above. I
#      didn't quite follow.
#
# Below are all the variables we want available outside configure.

AM_CONDITIONAL([ENABLE_CH_IMAGE], [test $enable_ch_image = yes])
AM_CONDITIONAL([ENABLE_HTML], [test $enable_html = yes])
AM_CONDITIONAL([ENABLE_LARK], [test $enable_bundled_lark = yes])
AM_CONDITIONAL([ENABLE_MAN], [test $enable_man = yes])
AS_IF([test $enable_syslog = yes],
      [AC_DEFINE([ENABLE_SYSLOG], [1], [log to syslog])])
AM_CONDITIONAL([ENABLE_TEST], [test $enable_test = yes])

AC_SUBST([CH_RUN_LIBS])
AC_SUBST([PYTHON_SHEBANG])
AC_SUBST([SPHINX])

AM_CONDITIONAL([HAVE_LIBSQUASHFUSE], [test $have_libsquashfuse = yes])
AS_IF([test $have_libsquashfuse = yes],
      [AC_DEFINE([HAVE_LIBSQUASHFUSE], [1], [link with libsquashfuse])])


### Prepare report ###########################################################

# FIXME: Should replace all these with macros?

# ch-run (needed below)

AS_IF([   test $have_userns = yes],
      [have_ch_run=yes],
      [have_ch_run=no])

# image builders

AS_IF([   test -n "$BUILDAH"],
      [have_buildah=yes],
      [have_buildah=no])

AS_IF([   test $enable_ch_image = yes \
       && test -n "$PYTHON" \
       && test -n "$PYTHON_SHEBANG" \
       && test -n "$REQUESTS" \
       && test $have_ch_run = yes],
      [have_ch_image=yes],
      [have_ch_image=no])

AS_IF([   test -n "$DOCKER" \
       && test -n "$MKTEMP"],
      [have_docker=yes],
      [have_docker=no])

# managing container images

AS_IF([   test $have_buildah = yes \
       || test $have_ch_image = yes \
       || test $have_docker = yes],
      [have_any_builder=yes],
      [have_any_builder=no])

AS_IF([   test $have_any_builder = yes],
      [have_dockerfile_build=yes],
      [have_dockerfile_build=no])

AS_IF([   test $have_any_builder = yes],
      [have_builder_to_tar=yes],
      [have_builder_to_tar=no])

AS_IF([   test $have_any_builder = yes \
       && test -n "$MKSQUASHFS"],
      [have_pack_squash=yes],
      [have_pack_squash=no])

# running containers

AS_IF([   test -n "$NVIDIA_CLI" \
       && test $have_nvidia_libs = yes],
      [have_nvidia=yes],
      [have_nvidia=no])

# test suite

AS_IF([   test $enable_test = yes \
       && test $have_ch_run = yes \
       && test $have_any_builder = yes \
       && test -n "$_BASH" \
       && test -n "$BATS" \
       && test -n "$WGET"],         # assume access to Docker Hub or mirror
      [have_tests_basic=yes],
      [have_tests_basic=no])

AS_IF([   test $have_tests_basic = yes \
       && test $have_docs = yes \
       && test -n "$SHELLCHECK" ],  # assume we do have generic sudo
       [have_tests_more=yes],
       [have_tests_more=no])

AS_IF([   test $have_tests_basic = yes \
       && test $have_tests_more = yes],
      [have_tests_tar=yes],
      [have_tests_tar=no])

AS_IF([   test $have_tests_basic = yes \
       && test $have_tests_more = yes \
       && test $have_pack_squash = yes ],
       [have_tests_squashunpack=yes],
       [have_tests_squashunpack=no])

AS_IF([   test $have_tests_squashunpack = yes \
       && test $have_libsquashfuse = yes],
       [have_tests_squashmount=yes],
       [have_tests_squashmount=no])


### Write output files #######################################################

AC_OUTPUT


## Print report

AS_IF([   test $have_userns = no \
       && test $chrooted = yes], [
  chroot_warning=$(cat <<'EOF'


    Warning: configure is running in a chroot, but user namespaces cannot be
    created in a chroot; see the man page unshare(2). Therefore, the above may
    be a false negative. However, note that like all the run-time configure
    tests, this is informational only and does not affect the build.
EOF
)
])

AC_MSG_NOTICE([

Dependencies report
===================

Below is a summary of configure's findings.

Caveats
~~~~~~~

Charliecloud's run-time dependencies are lazy; features just try to use their
dependencies and error if there's a problem. This report summarizes what
configure found on *this system*, because that's often useful, but none of the
run-time findings change what is built and installed.

Listed versions are minimums. These are a bit fuzzy. Try it even if configure
thinks a version is too old, and please report back to us.

Building Charliecloud
~~~~~~~~~~~~~~~~~~~~~

  will build and install:
    ch-image(1) ... ${enable_ch_image}
    HTML documentation ... ${enable_html}
    man pages ... ${enable_man}
    syslog ... ${enable_syslog}
    test suite ... ${enable_test}

  required:
    C99 compiler ... ${CC} ${CC_VERSION}

  ch-run(1) internal SquashFS mounting: ${have_libsquashfuse}
    enabled ... ${want_libsquashfuse}
    libfuse3 ... ${have_libfuse3}
    libsquashfuse_ll ... ${have_libsquashfuse_ll}
    ll.h header ... ${have_ll_h}

  documentation: ${have_docs}
    sphinx-build(1) ≥ $vmin_sphinx ... ${SPHINX_VERSION_NOTE}
    sphinx-build(1) Python ... ${sphinx_python:-n/a}
    "docutils" module ≥ $vmin_docutils ... ${DOCUTILS_VERSION_NOTE}
    "sphinx-rtd-theme" module ≥ $vmin_rtd ... ${RTD_VERSION_NOTE}

Building images
~~~~~~~~~~~~~~~

  with Buildah (warning: not tested; see issue #990): ${have_buildah}
    Buildah ≥ $vmin_buildah ... ${BUILDAH_VERSION_NOTE}

  with ch-image(1): ${have_ch_image}
    enabled ... ${enable_ch_image}
    Python shebang line ... ${PYTHON_SHEBANG:-none}
    Python in shebang ≥ $vmin_python ... ${PYTHON_VERSION_NOTE}
    "lark" module ... ${lark_status}
    "requests" module ≥ $vmin_requests ... ${REQUESTS_VERSION_NOTE}
    ch-run(1) ... ${have_ch_run}

  with Docker: ${have_docker}
    Docker ≥ $vmin_docker ... ${DOCKER_VERSION_NOTE}
    mktemp(1) ... ${MKTEMP:-not found}

Managing container images
~~~~~~~~~~~~~~~~~~~~~~~~~

  build from Dockerfile: ${have_dockerfile_build}
    at least one builder ... ${have_any_builder}
    access to an image repository ... assumed yes

  pack images from builder storage to tarball: ${have_builder_to_tar}
    at least one builder ... ${have_any_builder}

  pack images from builder storage to SquashFS: ${have_pack_squash}
    at least one builder ... ${have_any_builder}
    mksquashfs(1) ≥ $vmin_mksquashfs ... ${MKSQUASHFS_VERSION_NOTE}

  Note: Pulling/pushing images from/to a repository is currently done using
  the builder directly.

Running containers
~~~~~~~~~~~~~~~~~~

  ch-run(1): ${have_ch_run}
    user+mount namespaces ... ${have_userns}$chroot_warning

  run SquashFS images: ${have_any_squashfuse}
    manual mount with SquashFUSE ≥ $vmin_squashfuse ... ${SQUASHFUSE_VERSION_NOTE}
    internal mount with libsquashfuse ... ${have_libsquashfuse}

  inject nVidia GPU libraries: ${have_nvidia}
    nvidia-container-cli(1) ≥ $vmin_nvidia_cli ... ${NVIDIA_CLI_VERSION_NOTE}
    nVidia libraries & executables present ... ${have_nvidia_libs}

Test suite
~~~~~~~~~~

  basic tests, all stages: ${have_tests_basic}
    test suite enabled ... ${enable_test}
    ch-run(1) ... ${have_ch_run}
    any builder above ... ${have_any_builder}
    access to Docker Hub or mirror ... assumed yes
    Bats ≥ $vmin_bats ... ${BATS_VERSION_NOTE}
    Bash ≥ $vmin_bash ... ${_BASH_VERSION_NOTE}
    wget(1) ≥ $vmin_wget ... ${WGET_VERSION_NOTE}

  more complete tests: ${have_tests_more}
    basic tests ... ${have_tests_basic}
    documentation built ... ${have_docs}
    ShellCheck ≥ $vmin_shellcheck ... ${SHELLCHECK_VERSION_NOTE}
    generic sudo ... assumed yes

  recommended tests, tar-unpack mode: ${have_tests_tar}
    basic tests ... ${have_tests_basic}
    more tests ... ${have_tests_more}

  recommended tests, squash-unpack mode: ${have_tests_squashunpack}
    basic tests ... ${have_tests_basic}
    more tests ... ${have_tests_more}
    pack/unpack SquashFS images ... ${have_pack_squash}

  recommended tests, squash-mount mode: ${have_tests_squashmount}
    recommended, squash-unpack mode: ${have_tests_squashunpack}
    internal SquashFS mounting ... ${have_libsquashfuse}
])
