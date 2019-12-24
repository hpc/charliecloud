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

AM_INIT_AUTOMAKE([1.13 -Wall -Werror foreign subdir-objects])

AC_CONFIG_HEADERS([bin/config.h])
AC_CONFIG_FILES([Makefile
                 bin/Makefile
                 doc/Makefile
                 examples/Makefile
                 libexec/Makefile
                 misc/Makefile
                 packaging/Makefile
                 test/Makefile])

# Need a C99 compiler. (See https://stackoverflow.com/a/28558338.)
AC_PROG_CC
AC_DEFUN([CH_CFLAGS], [-std=c99 -Wpedantic -Wall -Werror])
AX_CHECK_COMPILE_FLAG([CH_CFLAGS], [
  CFLAGS+=" CH_CFLAGS"
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

AC_CHECK_FUNCS(asprintf, [], [
  AC_MSG_ERROR([asprintf() not found. Please report this bug.])])

vmin_sphinx=1.4.9
AX_WITH_PROG([SPHINX], [sphinx-build])
AC_SUBST([SPHINX])
CH_CHECK_VERSION([SPHINX], [$vmin_sphinx],
                 [--version | sed -E 's/sphinx-build //'])


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
python="${PYTHON_SHEBANG#/usr/bin/env }"                # use shell to find it
AS_CASE([$python],
  [/*], [PYTHON="$python"],                              # absolute
  [*],  [AC_CHECK_PROG([PYTHON], [$python], [$python])]  # verify it's in $PATH
)
CH_CHECK_VERSION([PYTHON], [$vmin_python], [--version | cut -d' ' -f2])

# Python module "lark-parser"
AS_IF([test -n "$PYTHON"], [
  AC_MSG_CHECKING([for lark-parser module])
  cat <<EOF | $PYTHON_SHEBANG
import sys
try:
   import lark
   lark.Visitor
except Exception:
   sys.exit(1)
EOF
  AS_IF([test $? -eq 0],
    [have_lark=yes],
    [have_lark=no])
  AC_MSG_RESULT($have_lark)
])

# skopeo
vmin_skopeo=0.1.30
AC_CHECK_PROG([SKOPEO], [skopeo], [skopeo])
CH_CHECK_VERSION([SKOPEO], [$vmin_skopeo], [--version | cut -d' ' -f3])

# SquashFUSE
vmin_squashfuse=0.1.102  # CentOS 7
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

# umoci
vmin_umoci=0.4.3
AC_CHECK_PROG([UMOCI], [umoci], [umoci])
CH_CHECK_VERSION([UMOCI], [$vmin_umoci], [--version | cut -d' ' -f3])

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

# Wget
vmin_wget=1.11  # 2008
AC_CHECK_PROG([WGET], [wget], [wget])
CH_CHECK_VERSION([WGET], [$vmin_wget], [--version | head -1 | cut -d' ' -f3])


## Adjust build options given what we have available.

AS_IF([test "$enable_html" = yes && test -z "$SPHINX"],
      [AC_MSG_WARN([forcing --disable-html: no suitable sphinx-build])
       enable_html=no])

AS_IF([test "$enable_man" = yes && test -z "$SPHINX"],
      [AC_MSG_WARN([forcing --disable-man: no suitable sphinx-build])
       enable_man=no])

## Set up Makefile conditionals.

AM_CONDITIONAL([ENABLE_HTML], [test $enable_html = yes])
AM_CONDITIONAL([ENABLE_MAN], [test $enable_man = yes])
AM_CONDITIONAL([ENABLE_TEST], [test $enable_test = yes])
AM_CONDITIONAL([ENABLE_CH_GROW], [test $enable_ch_grow = yes])


## Prepare run-time report.

# FIXME: Should replace all these with macros?

# ch-run (needed below)

AS_IF([   test $have_userns = yes],
      [have_ch_run=yes],
      [have_ch_run=no])

# image builders

AS_IF([   test -n "$BUILDAH_VERSION"],
      [have_buildah=yes],
      [have_buildah=no])

AS_IF([   test $enable_ch_grow = yes \
       && test -n "$PYTHON_VERSION" \
       && test -n "$PYTHON_SHEBANG" \
       && test $have_lark = yes \
       && test -n "$SKOPEO_VERSION" \
       && test -n "$UMOCI_VERSION" \
       && test $have_ch_run = yes],
      [have_ch_grow=yes],
      [have_ch_grow=no])

AS_IF([   test -n "$DOCKER_VERSION" \
       && test -n "$MKTEMP"],
      [have_docker=yes],
      [have_docker=no])

# managing container images

AS_IF([   test $have_buildah = yes \
       || test $have_ch_grow = yes \
       || test $have_docker = yes],
      [have_any_builder=yes],
      [have_any_builder=no])

AS_IF([test $have_any_builder = yes],
      [have_ch_build=yes],
      [have_ch_build=no])

AS_IF([test -n "$TAR"],
      [have_pack_tar=yes],
      [have_pack_tar=no])

AS_IF([   test $have_any_builder = yes \
       && test -n "$MKSQUASHFS_VERSION"],
      [have_pack_squash=yes],
      [have_pack_squash=no])

# running containers

AS_IF([test -n "$TAR"],
      [have_unpack_tar=yes],
      [have_unpack_tar=no])

AS_IF([test -n "$SQUASHFUSE_VERSION"],
      [have_ch_mount=yes],
      [have_ch_mount=no])

AS_IF([   test -n "$NVIDIA_CLI_VERSION" \
       && test $have_nvidia_libs = yes],
      [have_nvidia=yes],
      [have_nvidia=no])

# test suite

AS_IF([   test $enable_test = yes \
       && test $have_ch_run = yes \
       && test -n "$_BASH_VERSION" \
       && test -n "$BATS_VERSION" \
       && test -n "$WGET_VERSION"],
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
       && test -n "$SPHINX_VERSION"],
      [have_tests_all=yes],
      [have_tests_all=no])

## Done

AC_OUTPUT


## Print report

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

    C99 compiler ... ${CC} ${CC_VERSION}
    sphinx-build(1) $vmin_sphinx ... ${SPHINX:-not found} ${SPHINX_VERSION}

  will build and install:
    HTML documentation ... ${enable_html}
    man pages ... ${enable_man}
    test suite ... ${enable_test}
    ch-grow builder ... ${enable_ch_grow}

Image builders via our wrappers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  Buildah: ${have_buildah}
    Buildah $vmin_buildah ... ${BUILDAH_VERSION:-not found}

  ch-grow(1): ${have_ch_grow}
    ch-grow(1) enabled ... ${enable_ch_grow}
    Python shebang line ... ${PYTHON_SHEBANG:-none}
    Python in shebang 3.4 ... ${PYTHON_VERSION:-not found}
    "lark-parser" module ... ${have_lark}
    skopeo $vmin_skopeo ... ${SKOPEO_VERSION:-not found}
    umoci $vmin_umoci ... ${UMOCI_VERSION:-not found}
    ch-run(1) ... ${have_ch_run}

  Docker: ${have_docker}
    Docker $vmin_docker ... ${DOCKER_VERSION:-not found}
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
    mksquashfs(1) $vmin_mksquashfs ... ${MKSQUASHFS_VERSION}

  Note: Pulling/pushing images from/to a repository is currently done using
  the builder directly.

Running containers
~~~~~~~~~~~~~~~~~~

  ch-run(1): ${have_ch_run}
    user+mount namespaces ... ${have_userns}

  unpack image tarballs: ${have_unpack_tar}
    tar(1) ... ${TAR:-not found}

  ch-mount(1) and ch-umount(1) SquashFS images: ${have_ch_mount}
    SquashFUSE $vmin_squashfuse ... ${SQUASHFUSE_VERSION:-not found}

  inject nVidia GPU libraries: ${have_nvidia}
    nvidia-container-cli(1) $vmin_nvidia_cli ... ${NVIDIA_CLI_VERSION:-not found}
    nVidia libraries & executables present ... ${have_nvidia_libs}

Test suite
~~~~~~~~~~

  basic tests: ${have_tests_basic}
    test suite enabled ... ${enable_test}
    ch-run(1) ... ${have_ch_run}
    Bats $vmin_bats ... ${BATS_VERSION:-not found}
    Bash $vmin_bash ... ${_BASH_VERSION:-not found}
    wget(1) $vmin_wget ... ${WGET_VERSION:-not found}

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
    sphinx-build(1) $vmin_sphinx ... ${SPHINX_VERSION:-not found}
    generic sudo ... assumed yes
])
