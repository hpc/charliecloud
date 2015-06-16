#!/bin/bash

# Notes re. job output files:
#
# 1. (Kludge alert!) We truncate these files before each comparison so that we
#    can run the test script multiple times and compare against the latest
#    output. However, this does not update the file position pointers
#    maintained by QEMU. Therefore, when new output appears, it goes to the
#    same byte offset as would have been used without truncation, and the file
#    up to that offset is filled with zero bytes. The workaround is to use tr
#    to remove the zero bytes.
#
# 2. These log files have DOS-style line endings, not UNIX. Again, we use tr
#    to strip the extra carriage returns.

set -e

echo 'test output check'

while getopts '0iv' opt; do
    case $opt in
        0)
            echo 'evaluate node 0 only'
            node0=-0
            ;;
        i)
            echo 'interactive mode'
            interactive=-c
            ;;
        v)
            echo 'verbose mode'
            verbose=-v
            set -x
            ;;
        ?)
            echo 'usage error; aborting'
            exit 1;
            ;;
    esac
done

shift $(($OPTIND-1))

job=$1
test=$2
guest_ct=$(cat $job/meta/guest-count)

chbase=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)

if ( command -v colordiff &> /dev/null ); then
    diff=colordiff
else
    diff=diff
fi

function argparse() {
    idx=$1
    srcdir=$(readlink -f $(dirname $2))
    srcfile=$(basename $2)
    dstfile=$3
}

function ln_ () {
    argparse "$@"
    ln -f -s $srcdir/$srcfile $test/$idx/$dstfile
}

function tr_ () {
    sub=$1
    shift
    argparse "$@"
    tr -d "$sub" < $srcdir/$srcfile > $test/$idx/$dstfile
}


if [[ -z $job || -z $test ]]; then
    echo 'directory argument(s) missing; aborting'
    exit 1
fi

if [[ -n $interactive ]]; then
    echo 'truncating job stdout and stderr'
    truncate -s0 $job/out/*_job.{err,out}  # see truncation note above
    echo 'now run test (see documentation)'
    read -p 'press return when done --> ' line
fi

echo 'collecting files'
for (( i=0; i < $guest_ct; i++ )); do
    mkdir -p $test/$i

    echo "chgu$i" > $test/$i/hostname.expected

    tr_ '\0\r' $i $job/out/${i}_job.err job.err.actual
    ln_ $i $chbase/test/job.err job.err.expected
    tr_ '\0\r' $i $job/out/${i}_job.out job.out.actual
    ln_ $i $chbase/test/job.out job.out.expected

    ( id \
        | sed -r 's/groups=//' \
        | tr ' ,' '\n' \
        | sed -r 's/^(uid=[0-9]+)\([^)]+\)$/\1(charlie)/' \
        | sed -r 's/^gid=[0-9+].+$/gid=65530(charlie)/' \
        | egrep '^[a-z]|[0-9]{4,}|[5-9][0-9]{2}'
      echo '65530(charlie)' ) | sort > $test/$i/id-charlie.expected

    ln_ $i $job/meta/test/$i/route.expected route.expected
    ln_ $i $job/meta/test/$i/vars-charlie.expected vars-charlie.expected

    tr_ "'" $i $job/meta/proxy.sh vars-proxy.expected
    tr_ "'" $i $job/meta/proxy.sh vars-proxy-sudo.expected

done

echo 'evaluating results'
for (( i=0; i < $guest_ct; i++ )); do
    if [[ $i > 0 && -n $node0 ]]; then
        echo 'skipping remaining evaluations per -0'
        break
    fi
    echo "node $i test output start (no output = pass)"
    for actual in $test/$i/*.actual; do
        expected=${actual/%.actual/.expected}
        $diff -u $expected $actual || true
    done
    echo "node $i internet results:"
    sed 's/^/  /' $test/$i/wget.net
done
