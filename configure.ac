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
AC_CONFIG_MACRO_DIRS([misc/m4])

AC_CANONICAL_HOST
AS_CASE([$host_os],
  [linux*], [],
  [*],      [AC_MSG_ERROR([Linux is the only supported OS; see issue @%:@42.])]
)

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

# Need a C99 compiler. (See https://stackoverflow.com/a/28558338.)
AC_PROG_CC

# Set up CFLAGS.
ch_cflags='-std=c99 -Wpedantic -Wall'

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

AC_MSG_NOTICE([use_werror: $use_werror])
AS_IF([test $use_werror = yes], [ch_cflags+=' -Werror'])

AX_CHECK_COMPILE_FLAG([$ch_cflags], [
  CFLAGS+=" $ch_cflags"
], [
  AC_MSG_ERROR([no suitable C99 compiler found])
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

AC_ARG_ENABLE([html],
  AS_HELP_STRING([--disable-html], [HTML documentation]),
  [], [enable_html=yes])

AC_ARG_ENABLE([man],
  AS_HELP_STRING([--disable-man], [man pages]),
  [], [enable_man=yes])

AC_ARG_ENABLE([test],
  AS_HELP_STRING([--disable-test], [test suite]),
  [], [enable_test=yes])

AC_ARG_ENABLE([ch-grow],
  AS_HELP_STRING([--disable-ch-grow],
                 [ch-grow unprivileged builder and ch-tug]),
  [], [enable_ch_grow=yes])


## Feature test macros

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


## Feature tests - build time

# asprintf(3)
#
# You can do this with AC_CHECK_FUNC or AC_CHECK_FUNCS, but those macros call
# the function with no arguments. This causes a warning for asprintf() for
# some compilers (and I have no clue why others accept it); see issue #798.
# Instead, try to build a small test program that calls asprintf() correctly.
AC_MSG_CHECKING([for asprintf])
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
   AC_MSG_ERROR([asprintf() not found, and we have no workaround; see config.log.])])

#AC_CHECK_FUNCS(asprintfxxx, [], [
#  AC_MSG_ERROR([asprintf() not found. Please report this bug.])])

# Sphinx
vmin_sphinx=1.2.3
AX_WITH_PROG([SPHINX], [sphinx-build])
AC_SUBST([SPHINX])
CH_CHECK_VERSION([SPHINX], [$vmin_sphinx],
                 [--version | sed -E 's/sphinx-build //'])

# Get the Sphinx Python. We don't care about version.
AS_IF([test -n "$SPHINX"], [
  AS_IF([test -z "$sphinx_python"], [
    AC_MSG_CHECKING([for sphinx-build Python])
    sphinx_python=$(head -1 "$SPHINX" | sed -E 's/^..//')
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
])

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
])


## Feature tests - run time

# Bash
vmin_bash=4.1
AC_CHECK_PROG([_BASH], [bash], [bash])  # $BASH and $BASH_VERSION already used
CH_CHECK_VERSION([_BASH], [$vmin_bash], [--version | head -1 | cut -d' ' -f4])

# Bats
vmin_bats=0.4.0
AC_CHECK_PROG([BATS], [bats], [bats])
CH_CHECK_VERSION([BATS], [$vmin_bats], [--version | cut -d' ' -f2])

# Buildah
vmin_buildah=1.11.2
AC_CHECK_PROG([BUILDAH], [buildah], [buildah])
CH_CHECK_VERSION([BUILDAH], [$vmin_buildah], [--version | cut -d' ' -f3])

# Docker
vmin_docker=17.03
AC_CHECK_PROG([DOCKER], [docker], [docker])
CH_CHECK_VERSION([DOCKER], [$vmin_docker], [-v | tr -d , | cut -d' ' -f3])

# mksquashfs
vmin_mksquashfs=4.2  # CentOS 7
AC_CHECK_PROG([MKSQUASHFS], [mksquashfs], [mksquashfs])
CH_CHECK_VERSION([MKSQUASHFS], [$vmin_mksquashfs],
                 [-version | head -1 | cut -d' ' -f3])

# mktemp - no version
AC_CHECK_PROG([MKTEMP], [mktemp], [mktemp])

# libnvidia-container-cli
vmin_nvidia_cli=1.0.0
AC_CHECK_PROG([NVIDIA_CLI], [nvidia-container-cli], [nvidia-container-cli])
CH_CHECK_VERSION([NVIDIA_CLI], [$vmin_nvidia_CLI],
                 [-V | head -1 | cut -d' ' -f2])
AC_MSG_CHECKING([for nVidia libraries & executables])
AS_IF([test -n "$NVIDIA_CLI_VERSION"],
  [AS_IF([nvidia-container-cli list | grep -Fq libnvidia-glcore.so],
        [have_nvidia_libs=yes],
        [have_nvidia_libs=no])],
  [have_nvidia_libs=no])
AC_MSG_RESULT($have_nvidia_libs)

# Python
vmin_python=3.4
AC_MSG_CHECKING([if "$PYTHON_SHEBANG" starts with slash])
AS_CASE([$PYTHON_SHEBANG],
  [/*], [AC_MSG_RESULT([ok])],
  [*],  [AC_MSG_RESULT([no])
         AC_MSG_ERROR([--with-python: must start with slash])])
AC_SUBST([PYTHON_SHEBANG])
python="${PYTHON_SHEBANG#/usr/bin/env }"                # use shell to find it
AS_CASE([$python],
  [/*], [PYTHON="$python"],                              # absolute
  [*],  [AC_CHECK_PROG([PYTHON], [$python], [$python])]  # verify it's in $PATH
)
CH_CHECK_VERSION([PYTHON], [$vmin_python], [--version | cut -d' ' -f2])

# Python module "lark-parser"
vmin_lark=0.7.1
AS_IF([test -n "$PYTHON"], [
  AC_MSG_CHECKING([for lark-parser module])
  cat <<EOF | $PYTHON_SHEBANG
import sys
try:
   import lark   # module present?
   lark.Visitor  # correct module? (there are two)
except Exception:
   sys.exit(1)
EOF
  AS_IF([test $? -eq 0],
    [LARK=$PYTHON; have_lark=yes],
    [LARK=;        have_lark=no])
  AC_MSG_RESULT([$have_lark])
  CH_CHECK_VERSION([LARK], [$vmin_lark],
    [-c 'import lark; print(lark.__version__)'])
])

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

# ShellCheck
vmin_shellcheck=0.6.0
AC_CHECK_PROG([SHELLCHECK], [shellcheck], [shellcheck])
# https://stackoverflow.com/questions/6022384
CH_CHECK_VERSION([SHELLCHECK], [$vmin_shellcheck],
                 [--version | sed -n '2{s/^version: //;p;q}'])

# SquashFUSE
vmin_squashfuse=0.1.100  # Ubuntu 16.04 (Xenial). CentOS 7 has 0.1.102.
AC_CHECK_PROG([SQUASHFUSE], [squashfuse], [squashfuse])
CH_CHECK_VERSION([SQUASHFUSE], [$vmin_squashfuse],
                 [--help |& head -1 | cut -d' ' -f2])

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

# tar (yes, we can confidently assume tar, but this makes the report clearer)
AC_CHECK_PROG([TAR], [tar], [tar])

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
  [have_userns=yes
   AC_DEFINE(HAVE_USERNS, 1, [user+mount namespaces work])],
  [have_userns=no],
  [AC_MSG_ERROR([cross-compilation not supported])])
AC_MSG_RESULT($have_userns)

# Wget
vmin_wget=1.11  # 2008
AC_CHECK_PROG([WGET], [wget], [wget])
CH_CHECK_VERSION([WGET], [$vmin_wget], [--version | head -1 | cut -d' ' -f3])


## Adjust build options given what we have available.

AS_IF([   test -n "$SPHINX" \
       && test -n "$DOCUTILS" \
       && test -n "$RTD"],
       [have_docs=yes],
       [have_docs=no])

AS_IF([   test $enable_html = yes && test $have_docs = no],
      [AC_MSG_WARN([forcing --disable-html: no suitable sphinx-build])
       enable_html=no])

AS_IF([   test $enable_man = yes && test $have_docs = no],
      [AC_MSG_WARN([forcing --disable-man: no suitable sphinx-build])
       enable_man=no])

## Set up Makefile conditionals.

AM_CONDITIONAL([ENABLE_HTML], [test $enable_html = yes])
AM_CONDITIONAL([ENABLE_MAN], [test $enable_man = yes])
AM_CONDITIONAL([ENABLE_TEST], [test $enable_test = yes])
AM_CONDITIONAL([ENABLE_CH_GROW], [test $enable_ch_grow = yes])


## Prepare report.

# FIXME: Should replace all these with macros?

# ch-run (needed below)

AS_IF([   test $have_userns = yes],
      [have_ch_run=yes],
      [have_ch_run=no])

# image builders

AS_IF([   test -n "$BUILDAH"],
      [have_buildah=yes],
      [have_buildah=no])

AS_IF([   test $enable_ch_grow = yes \
       && test -n "$PYTHON" \
       && test -n "$PYTHON_SHEBANG" \
       && test -n "$LARK" \
       && test -n "$REQUESTS" \
       && test $have_ch_run = yes],
      [have_ch_grow=yes],
      [have_ch_grow=no])

AS_IF([   test -n "$DOCKER" \
       && test -n "$MKTEMP"],
      [have_docker=yes],
      [have_docker=no])

# managing container images

AS_IF([   test $have_buildah = yes \
       || test $have_ch_grow = yes \
       || test $have_docker = yes],
      [have_any_builder=yes],
      [have_any_builder=no])

AS_IF([   test $have_any_builder = yes],
      [have_ch_build=yes],
      [have_ch_build=no])

AS_IF([   test -n "$TAR"],
      [have_pack_tar=yes],
      [have_pack_tar=no])

AS_IF([   test $have_any_builder = yes \
       && test -n "$MKSQUASHFS"],
      [have_pack_squash=yes],
      [have_pack_squash=no])

# running containers

AS_IF([   test -n "$TAR"],
      [have_unpack_tar=yes],
      [have_unpack_tar=no])

AS_IF([   test -n "$SQUASHFUSE"],
      [have_ch_mount=yes],
      [have_ch_mount=no])

AS_IF([   test -n "$NVIDIA_CLI" \
       && test $have_nvidia_libs = yes],
      [have_nvidia=yes],
      [have_nvidia=no])

# test suite

AS_IF([   test $enable_test = yes \
       && test $have_ch_run = yes \
       && test -n "$_BASH" \
       && test -n "$BATS" \
       && test -n "$WGET"],
      [have_tests_basic=yes],
      [have_tests_basic=no])

AS_IF([   test $have_tests_basic = yes \
       && test $have_any_builder = yes \
       && test $have_pack_tar = yes \
       && test $have_unpack_tar = yes],
      [have_tests_tar=yes],
      [have_tests_tar=no])

AS_IF([   test $have_tests_tar = yes \
       && test $have_pack_squash = yes \
       && test $have_ch_mount = yes],
      [have_tests_squash=yes],
      [have_tests_squash=no])

# assumes we do have generic sudo
AS_IF([   test $have_tests_squash = yes \
       && test -n "$SPHINX" \
       && test -n "$SHELLCHECK"],
      [have_tests_all=yes],
      [have_tests_all=no])

## Done

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

  required:
    C99 compiler ... ${CC} ${CC_VERSION}

  documentation: ${have_docs}
    sphinx-build(1) ≥ $vmin_sphinx ... ${SPHINX_VERSION_NOTE}
    sphinx-build(1) Python ... ${sphinx_python:-n/a}
    "docutils" module ≥ $vmin_docutils ... ${DOCUTILS_VERSION_NOTE}
    "sphinx-rtd-theme" module ≥ $vmin_rtd ... ${RTD_VERSION_NOTE}

  will build and install:
    HTML documentation ... ${enable_html}
    man pages ... ${enable_man}
    test suite ... ${enable_test}
    ch-grow(1) and ch-tug(1) ... ${enable_ch_grow}

Building images via our wrappers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  with Buildah: ${have_buildah}
    Buildah ≥ $vmin_buildah ... ${BUILDAH_VERSION_NOTE}

  with ch-grow(1): ${have_ch_grow}
    enabled ... ${enable_ch_grow}
    Python shebang line ... ${PYTHON_SHEBANG:-none}
    Python in shebang ≥ $vmin_python ... ${PYTHON_VERSION_NOTE}
    "lark-parser" module ≥ $vmin_lark ... ${LARK_VERSION_NOTE}
    "requests" module ≥ $vmin_requests ... ${REQUESTS_VERSION_NOTE}
    ch-run(1) ... ${have_ch_run}

  with Docker: ${have_docker}
    Docker ≥ $vmin_docker ... ${DOCKER_VERSION_NOTE}
    mktemp(1) ... ${MKTEMP:-not found}

Managing container images
~~~~~~~~~~~~~~~~~~~~~~~~~

  build from Dockerfile with ch-build(1): ${have_ch_build}
    at least one builder ... ${have_any_builder}
    access to an image repository ... assumed yes

  pack images from builder storage to tarball: ${have_pack_tar}
    at least one builder ... ${have_any_builder}
    tar(1) ... ${TAR:-not found}

  pack images from builder storage to SquashFS: ${have_pack_squash}
    at least one builder ... ${have_any_builder}
    mksquashfs(1) ≥ $vmin_mksquashfs ... ${MKSQUASHFS_VERSION_NOTE}

  Note: Pulling/pushing images from/to a repository is currently done using
  the builder directly.

Running containers
~~~~~~~~~~~~~~~~~~

  ch-run(1): ${have_ch_run}
    user+mount namespaces ... ${have_userns}$chroot_warning

  unpack image tarballs: ${have_unpack_tar}
    tar(1) ... ${TAR:-not found}

  ch-mount(1) and ch-umount(1) SquashFS images: ${have_ch_mount}
    SquashFUSE ≥ $vmin_squashfuse ... ${SQUASHFUSE_VERSION_NOTE}

  inject nVidia GPU libraries: ${have_nvidia}
    nvidia-container-cli(1) ≥ $vmin_nvidia_cli ... ${NVIDIA_CLI_VERSION_NOTE}
    nVidia libraries & executables present ... ${have_nvidia_libs}

Test suite
~~~~~~~~~~

  basic tests: ${have_tests_basic}
    test suite enabled ... ${enable_test}
    ch-run(1) ... ${have_ch_run}
    Bats ≥ $vmin_bats ... ${BATS_VERSION_NOTE}
    Bash ≥ $vmin_bash ... ${_BASH_VERSION_NOTE}
    wget(1) ≥ $vmin_wget ... ${WGET_VERSION_NOTE}

  recommended tests with tarballs: ${have_tests_tar}
    basic tests ... ${have_tests_basic}
    any builder above ... ${have_any_builder}
    access to Docker Hub or mirror ... assumed yes
    pack images with tar ... ${have_pack_tar}
    unpack images with tar ... ${have_unpack_tar}

  recommended tests with SquashFS: ${have_tests_squash}
    recommended tests with tar ... ${have_tests_tar}
    pack images with SquashFS ... ${have_pack_squash}
    mount/unmount SquashFS images ... ${have_ch_mount}

  complete test suite: ${have_tests_all}
    recommended tests with SquashFS ... ${have_tests_squash}
    documentation ... ${have_docs}
    ShellCheck ≥ $vmin_shellcheck ... ${SHELLCHECK_VERSION_NOTE}
    generic sudo ... assumed yes
])
