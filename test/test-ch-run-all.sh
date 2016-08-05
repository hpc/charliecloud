#!/bin/bash

usage () {
    cat 1>&2 <<EOF
Isolation test driver for multiple variations of test-ch-run.sh

Usage:

  $ $(basename $0) [-h] NEWROOT TESTDIR [PDIR1 [PDIR1] ...]

TESTDIR is used for test scratch space and output.

PERMDIRn are perms_test directories created with make-perms-test. These must
be crated with "you" being "nobody".

Summary of all tests with no chatter appears in TESTDIR/summary.
Standard output from this script appears in TESTDIR/stdout.

EOF
    exit 1
}

set -e

if [[ $# -lt 2 || $1 = '-h' ]]; then
    usage
    exit 1
fi

IMAGE="$1"
TESTDIR="$2"
shift 2

IHOME=$(readlink -f $(dirname $0))

mkdir $TESTDIR

# Redirect stdout through tee (http://stackoverflow.com/a/3403786/396038)
exec > >(tee -i $TESTDIR/stdout)


GID=$(id -g)

for cuid in $UID 0 65534; do
    for cgid in $GID 0 65534; do
        subt="$TESTDIR/$cuid,$cgid"
        $IHOME/test-ch-run.sh -u$cuid -g$cgid $IMAGE $subt "$@" | tee $subt.out
        if [[ ! -d $TESTDIR/$tag ]]; then
            echo 'no test directory found' 1>&2
            exit 1
        fi
    done
done

summary=$TESTDIR/summary
cat $TESTDIR/*.out | egrep -v '^(#|$)' | sort > $summary

echo
echo '### Summary'
printf '# total tests:  %3d\n' $(wc -l < $summary)
printf '# SAFE result:  %3d\n' $(fgrep -c $'\tSAFE\t' < $summary)
printf '# other result: %3d\n' $(fgrep -vc $'\tSAFE\t' < $summary)
