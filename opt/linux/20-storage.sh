#!/bin/bash

. $(dirname $0)/charlie.sh
. $(dirname $0)/util.sh

TMPDISK=/dev/vdb
TMPSWAP=/dev/vdb1
TMPFS=/dev/vdb2

log 'partitioning temporary disk'
if (sgdisk --info=1 $TMPDISK | fgrep -q 'does not exist'); then
    log 'no partition table found, proceeding'
    sgdisk --new=1:0:+2G $TMPDISK
    sgdisk --typecode=1:8200 $TMPDISK
    sgdisk --new=2:0:0 $TMPDISK
    sgdisk --print $TMPDISK
    log 'formatting swap space'
    mkswap -L tmpswap $TMPSWAP
    log 'creating temporary filesystem'
    mkfs.ext4 -q -L tmp -m 0 -O uninit_bg,^has_journal,sparse_super $TMPFS
else
    log 'temporary disk is already partitioned, skipping (did you reboot?)'
fi

log 'mounting temporary storage'
mount $CH_TMP
chmod 1777 $CH_TMP
if [ $(wc -l < /proc/swaps) = '1' ]; then
    log 'activating swap'
    swapon -L tmpswap  # mount -a doesn't work for some reason
else
    log 'swap already active, skipping'
fi
