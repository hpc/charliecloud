#!/bin/bash

set -e

DATADIR=test
mkdir $DATADIR

cd $DATADIR
mkdir -p err

# Who is running the test?
echo $UID > uid
echo $USER > user

# Find root device and options.
fgrep " / " /proc/mounts > rootmount
cat rootmount | cut -d' ' -f1 > rootdev
cat rootmount | cut -d' ' -f3 > roottype
cat rootmount | cut -d' ' -f4 > rootopts

# Find IP non-loopback addresses.
mkdir ip
for addr in $(hostname --all-ip-addresses); do
    touch ip/$addr
done

echo $DATADIR
