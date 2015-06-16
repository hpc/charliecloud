#!/bin/bash

set -e

while getopts '0civ' opt; do
    case $opt in
        0)
            node0=-0
            ;;
        c)
            commit='--commit 0'
            ;;
        i)
            interactive='-i --curses'
            ;;
        i)
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

image=$1

if [[ -z $image ]]; then
    echo 'no image specified; aborting'
    exit 1
fi

chbase=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
job=charlie-test
test=testout
data2=$test/data2
data3=$test/data3
data4=$test/data4
node_ct=3
core_ct=2
tmpsize=4G

cat <<EOF
configuration...
  node 0 only:  $node0
  commit:       $commit
  interactive:  $interactive
  verbose:      $verbose
starting test cluster...
  image:        $image
  base dir:     $chbase
  job dir:      $job
  test dir:     $test
  nodes:        $node_ct
  cores/node:   $core_ct
  tmp-size:     $tmpsize
EOF

mkdir -p $test $data2 $data3 $data4

$chbase/bin/vcluster \
    $commit \
    --cores $core_ct \
    -d $test \
    -d $data2 \
    -d $data3 \
    -d $data4 \
    $interactive \
    -n $node_ct \
    --job $chbase/test/job.sh \
    --jobdir $job \
    --tmp-size $tmpsize \
    $image

if [[ -n $interactive ]]; then
    echo 'interactive mode; skipping evaluation'
else
    $chbase/test/evaluate.sh $node0 $interactive $verbose $job $test
fi
