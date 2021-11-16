#!/bin/bash

# Authentication helper for RStudio Server. Accepts username on $1 and reads
# password from stdin after prompting. The purpose is to provide a simple gate
# that prevents people from easily connecting to Rstudio Server during the
# test. The username is not validated. The password is checked against
# $BATS_TMPDIR/rserver-password.txt, which should be populated earlier in the
# test.
#
# See also:
# https://github.com/nickjer/singularity-rstudio/blob/bce2531/rstudio_auth.sh

[[ $# -ge 1 ]]  # validate args

password_expected=$(cat "$BATS_TMPDIR"/rserver-password.txt)
read -rsp 'Password: ' password_actual
echo
[[ $password_actual = "$password_expected" ]]
