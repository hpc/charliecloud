#!/bin/bash

DATADIR=$(mktemp -d)

cd $DATADIR
mkdir -p err

# Who is running the test?
echo $UID > uid
echo $USER > user

# Find root device major and minor numbers.
# FIXME: what about lustre, NFS mounts?
rootdev=$(mount | fgrep 'on / ' | cut -d' ' -f1)
if [[ $rootdev =~ /dev ]]; then
    stat -c '%t' $rootdev > rootmajor_hex
    stat -c '%T' $rootdev > rootminor_hex
fi

# Find IP non-loopback addresses.
mkdir ip
for addr in $(hostname --all-ip-addresses); do
    touch ip/$addr
done

echo $DATADIR
