AC_PREREQ([2.69])
m4_include([custom_help.m4])
AC_INIT([charliecloud], [0.11], [https://github.com/hpc/charliecloud])
AC_CONFIG_SRCDIR([bin/version.h])
AC_CONFIG_HEADERS([config.h])

# Checks for programs.
AC_PROG_CC
# Needed for C11 to work
AC_PROG_CC_STDC
AC_PROG_MAKE_SET

# Checks for libraries.
AC_CHECK_LIB([rt], [clock_gettime])

AC_CONFIG_FILES([Makefile
                 bin/Makefile
                 test/Makefile
                 doc-src/Makefile
                 ])

AC_CONFIG_AUX_DIR([build-aux])

AM_INIT_AUTOMAKE([-Wall foreign subdir-objects])

# Condtional for the tests WIP
#AM_CONDITIONAL([TEST], [test $CH_TEST_SCOPE = quick])
#AM_CONDITIONAL([VERSION], [test $CH_TEST_SCOPE = quick])

# Conditional to check if usernamespaces are enabled
#NAMEPSACES=`grep -oP "user.max_user_namespaces=\K[0-9]*" /etc/sysctl.conf)`
#AC_DEFINE_UNQUOTED([NAMESPACES],
#                   ["$NAMESPACES"],
#                   [Check if namespaces are enabled])

##AM_CONDITIONAL([NAMESPACES], [test "$NAMESPACES" = 0]

AC_ARG_ENABLE(docs,
	AC_HELP_STRING([--enable_docs],
 		[Build the docs]),
    [enable_docs=$enableval],
    [enable_docs="no"])

AC_ARG_ENABLE(tests,
	AC_HELP_STRING([--disable_tests],
 		[Build the test suite]),
    [disable_tests=$enableval],
    [disable_tests="yes"])

AC_ARG_ENABLE(docker,
	AC_HELP_STRING([--disable_docker],
        [Disable docker support]),
    [disable_docker=$enableval],
    [disable_docker="no"])

AC_ARG_ENABLE(ch-grow,
	AC_HELP_STRING([--disable_chgrow],
        [Disable chgrow support]),
    [disable_chgrow=$enableval],
    [disable_chgrow="no"])

AC_ARG_ENABLE(buildah,
	AC_HELP_STRING([--disable_buildah],
        [Disable buildah support]),
    [disable_buildah=$enableval],
    [disable_buildah="no"])

# Write the configure script
AC_OUTPUT
